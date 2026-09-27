//+------------------------------------------------------------------+
//|                    FVG_Scalper_V2_12_Research.mq5                |
//|      Research edition based on FVG_Scalper_V2_AutoLot v2.11     |
//|      Core FVG logic preserved; instrumentation + safety added     |
//+------------------------------------------------------------------+
#property strict
#property version   "2.12"
#property description "FVG V2.12 Research: preserves V2.11 FVG/retest logic and staged management, adds hard risk/margin guards, persistent zone/day state, trade telemetry (R/MFE/MAE/slippage/effective risk), direction controls, session tags, and stop-modification diagnostics."

#include <Trade/Trade.mqh>
CTrade trade;

//--------------------------- Strategy -------------------------------
input group "Strategy"
input ENUM_TIMEFRAMES InpEntryTF = PERIOD_M1;
input ENUM_TIMEFRAMES InpBiasTF = PERIOD_M1;
input int InpBiasFastEMA = 20;
input int InpBiasSlowEMA = 50;
input bool InpUseBiasFilter = false;
input bool InpAllowLong = true;
input bool InpAllowShort = true;
input bool InpRequireMidpoint = false;
input bool InpRequireRejection = true;
input double InpMinFVG_ATR = 0.15;
input double InpMinBody_ATR = 0.50;
input double InpMinBodyRatio = 0.60;
input int InpMaxFVG_Bars = 1000;
input bool InpReplaceWithNewFVG = true;
input bool InpOneTradePerFVG = true;

//------------------------ Risk Management ----------------------------
input group "Risk Management"
input double InpRiskPercent = 1.0;              // safer research default
input bool InpAutoCompoundLots = true;
input double InpCompoundingBaseBalance = 100.0;
input bool InpUseHardRiskCap = true;
input double InpMaxEffectiveRiskPct = 1.25;      // blocks min-lot / calc overshoot
input double InpMaxLots = 0.0;                   // 0 = broker maximum
input double InpRewardRisk = 30.0;               // kept for V2.11 comparability
input double InpMaxSL_ATR = 3.0;
input int InpATRPeriod = 14;
input double InpSL_ATR_Buffer = 0.15;
input bool InpUseProfitLock = true;
input double InpLock1TriggerRR = 0.50;
input double InpLock1RR = 0.10;
input double InpLock2TriggerRR = 1.00;
input double InpLock2RR = 0.35;
input bool InpUseATRTrail = true;
input double InpTrailStartRR = 1.50;
input double InpTrail_ATR = 0.10;

//--------------------------- Sessions --------------------------------
input group "Sessions"
input bool InpUseSession1 = true;
input int InpSession1Start = 0;
input int InpSession1End = 0;
input bool InpUseSession2 = true;
input int InpSession2Start = 0;
input int InpSession2End = 0;
input int InpMaxSpreadPoints = 80;
input int InpMaxTradesDay = 30;
input double InpDailyLossPct = 3.0;
input bool InpOnePosition = true;

//----------------------- Execution Safety -----------------------------
input group "Execution Safety"
input bool InpUseMarginGuard = true;
input double InpMinProjectedMarginLevelPct = 150.0;
input double InpMaxSingleTradeMarginPct = 35.0;
input int InpMaxEntrySlippagePoints = 0;          // 0 = log only; >0 rejects post-fill telemetry flag only
input int InpCooldownSeconds = 0;

//--------------------------- Research ---------------------------------
input group "Research / Telemetry"
input bool InpEnableTelemetry = true;
input string InpTelemetryFile = "FVG_V2_12_Research.csv";
input bool InpPersistState = true;
input int InpResearchSessionOffsetHours = 0;      // server-time adjustment for labels only
input bool InpVerboseLog = false;

//--------------------------- Execution --------------------------------
input group "Execution"
input ulong InpMagic = 26081112;
input int InpDeviationPoints = 30;

struct FVGZone
{
   bool valid;
   bool bullish;
   double low;
   double high;
   datetime formed;
   int shift;
   bool traded;
};

struct TradeTelemetry
{
   bool active;
   ulong positionTicket;
   long positionType;
   datetime entryTime;
   double requestedEntry;
   double actualEntry;
   double initialSL;
   double originalTP;
   double initialRiskPrice;
   double plannedRiskMoney;
   double effectiveRiskMoney;
   double effectiveRiskPct;
   double requestedRawVolume;
   double volume;
   double maxMFE_R;
   double maxMAE_R;
   double entrySlippagePoints;
   double entrySpreadPoints;
   string sessionTag;
   datetime zoneFormed;
   double zoneLow;
   double zoneHigh;
   bool bullishZone;
};

int hATR = INVALID_HANDLE;
int hFastEMA = INVALID_HANDLE;
int hSlowEMA = INVALID_HANDLE;
datetime g_lastBar = 0;
FVGZone g_zone;
TradeTelemetry g_track;
int g_dayKey = -1;
int g_tradesToday = 0;
double g_dayStartEquity = 0.0;
datetime g_lastEntryTime = 0;

// Global-variable key prefix for restart-safe state.
string GVPrefix()
{
   return "FVG212_" + _Symbol + "_" + IntegerToString((int)InpMagic) + "_";
}

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpRiskPercent <= 0.0 || InpRewardRisk <= 0.0 || InpATRPeriod < 1)
      return INIT_PARAMETERS_INCORRECT;
   if(InpMinBodyRatio <= 0.0 || InpMinBodyRatio > 1.0)
      return INIT_PARAMETERS_INCORRECT;
   if(InpUseHardRiskCap && InpMaxEffectiveRiskPct <= 0.0)
      return INIT_PARAMETERS_INCORRECT;

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   hATR = iATR(_Symbol, InpEntryTF, InpATRPeriod);
   hFastEMA = iMA(_Symbol, InpBiasTF, InpBiasFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA = iMA(_Symbol, InpBiasTF, InpBiasSlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(hATR == INVALID_HANDLE || hFastEMA == INVALID_HANDLE || hSlowEMA == INVALID_HANDLE)
      return INIT_FAILED;

   g_zone.valid = false;
   g_zone.traded = false;
   ResetTelemetry();

   if(InpPersistState)
      LoadZoneState();

   ResetDailyStats();
   RestoreTelemetryFromPosition();

   if(InpEnableTelemetry)
      EnsureTelemetryHeader();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(InpPersistState)
      SaveZoneState();

   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hFastEMA != INVALID_HANDLE) IndicatorRelease(hFastEMA);
   if(hSlowEMA != INVALID_HANDLE) IndicatorRelease(hSlowEMA);
}

//+------------------------------------------------------------------+
//| Main tick                                                         |
//+------------------------------------------------------------------+
void OnTick()
{
   ResetDailyStatsIfNeeded();
   UpdateTelemetryExcursions();
   ManageOpenPosition();

   if(IsNewBar())
      UpdateFVG();

   if(!TradingAllowed()) return;
   if(InpOnePosition && HasOurPosition()) return;
   if(g_tradesToday >= InpMaxTradesDay) return;
   if(!g_zone.valid) return;
   if(InpOneTradePerFVG && g_zone.traded) return;
   if(g_zone.bullish && !InpAllowLong) return;
   if(!g_zone.bullish && !InpAllowShort) return;
   if(!BiasAllows(g_zone.bullish)) return;
   if(!ZoneStillValid()) { g_zone.valid = false; PersistZoneIfNeeded(); return; }
   if(InpCooldownSeconds > 0 && g_lastEntryTime > 0 && (TimeCurrent() - g_lastEntryTime) < InpCooldownSeconds) return;

   TryFVGEntry();
}

//+------------------------------------------------------------------+
//| Trade transaction: capture realised exit                          |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   string sym = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   ulong magic = (ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(sym != _Symbol || magic != InpMagic)
      return;

   ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY)
      return;

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   double commission = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   double swap = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
   double fee = HistoryDealGetDouble(trans.deal, DEAL_FEE);
   double net = profit + commission + swap + fee;
   double closePrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   datetime closeTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);

   if(g_track.active)
   {
      UpdateTelemetryExcursions();
      double realizedR = (g_track.effectiveRiskMoney > 0.0) ? net / g_track.effectiveRiskMoney : 0.0;
      WriteTelemetryRow(closeTime, closePrice, net, realizedR, trans.deal);
      if(InpVerboseLog)
         Print("FVG212 exit | net=", DoubleToString(net,2), " R=", DoubleToString(realizedR,3),
               " MFE_R=", DoubleToString(g_track.maxMFE_R,3), " MAE_R=", DoubleToString(g_track.maxMAE_R,3));
      ResetTelemetry();
   }
}

//+------------------------------------------------------------------+
//| FVG discovery                                                     |
//+------------------------------------------------------------------+
void UpdateFVG()
{
   FVGZone newest;
   if(!FindNewestFVG(newest)) return;

   if(!g_zone.valid || (InpReplaceWithNewFVG && newest.formed > g_zone.formed) || FVGExpired(g_zone))
   {
      g_zone = newest;
      PersistZoneIfNeeded();
   }
}

bool FindNewestFVG(FVGZone &z)
{
   z.valid = false;
   z.traded = false;
   z.shift = -1;

   MqlRates r[];
   double atr[];
   ArraySetAsSeries(r, true);
   ArraySetAsSeries(atr, true);

   int need = MathMax(InpMaxFVG_Bars + 5, 30);
   if(CopyRates(_Symbol, InpEntryTF, 0, need, r) < 6) return false;
   if(CopyBuffer(hATR, 0, 0, need, atr) < 6) return false;

   for(int s=1; s<=InpMaxFVG_Bars && s+2<ArraySize(r); s++)
   {
      double a = atr[s];
      if(a <= 0) continue;

      double oh = r[s+2].high;
      double ol = r[s+2].low;
      double mo = r[s+1].open;
      double mc = r[s+1].close;
      double mh = r[s+1].high;
      double ml = r[s+1].low;
      double nh = r[s].high;
      double nl = r[s].low;
      double body = MathAbs(mc-mo);
      double range = mh-ml;

      if(body < a*InpMinBody_ATR) continue;
      if(range <= 0 || body/range < InpMinBodyRatio) continue;

      // Bullish FVG: candle s+2 high below candle s low, with bullish displacement candle.
      if(oh < nl)
      {
         double gap = nl-oh;
         if(gap >= a*InpMinFVG_ATR && mc > mo)
         {
            z.valid=true; z.bullish=true; z.low=oh; z.high=nl;
            z.formed=r[s].time; z.shift=s; z.traded=false;
            return true;
         }
      }

      // Bearish FVG: candle s+2 low above candle s high, with bearish displacement candle.
      if(ol > nh)
      {
         double gap = ol-nh;
         if(gap >= a*InpMinFVG_ATR && mc < mo)
         {
            z.valid=true; z.bullish=false; z.low=nh; z.high=ol;
            z.formed=r[s].time; z.shift=s; z.traded=false;
            return true;
         }
      }
   }
   return false;
}

bool ZoneStillValid()
{
   if(!g_zone.valid || FVGExpired(g_zone)) return false;

   MqlRates r[];
   ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol, InpEntryTF, 0, 3, r) < 3) return false;
   double c = r[1].close;

   if(g_zone.bullish && c < g_zone.low) return false;
   if(!g_zone.bullish && c > g_zone.high) return false;
   return true;
}

bool FVGExpired(const FVGZone &z)
{
   if(!z.valid) return true;
   int sh = iBarShift(_Symbol, InpEntryTF, z.formed, false);
   return sh < 0 || sh > InpMaxFVG_Bars;
}

//+------------------------------------------------------------------+
//| Entry                                                              |
//+------------------------------------------------------------------+
void TryFVGEntry()
{
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(bid<=0 || ask<=0) return;

   double midpoint=(g_zone.low+g_zone.high)/2.0;

   if(g_zone.bullish)
   {
      if(!InpAllowLong) return;
      if(ask < g_zone.low || ask > g_zone.high) return;
      if(InpRequireMidpoint && ask > midpoint) return;
      if(InpRequireRejection && !BullishRejection()) return;
      if(OpenTrade(true,g_zone))
      {
         g_zone.traded=true;
         PersistZoneIfNeeded();
      }
   }
   else
   {
      if(!InpAllowShort) return;
      if(bid < g_zone.low || bid > g_zone.high) return;
      if(InpRequireMidpoint && bid < midpoint) return;
      if(InpRequireRejection && !BearishRejection()) return;
      if(OpenTrade(false,g_zone))
      {
         g_zone.traded=true;
         PersistZoneIfNeeded();
      }
   }
}

bool BullishRejection()
{
   MqlRates r[]; ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,InpEntryTF,0,2,r)<2) return false;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double range=r[0].high-r[0].low;
   if(range<=0) return false;
   double closePos=(bid-r[0].low)/range;
   return closePos >= 0.55;
}

bool BearishRejection()
{
   MqlRates r[]; ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,InpEntryTF,0,2,r)<2) return false;
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double range=r[0].high-r[0].low;
   if(range<=0) return false;
   double closePos=(ask-r[0].low)/range;
   return closePos <= 0.45;
}

bool BiasAllows(bool bullish)
{
   if(!InpUseBiasFilter) return true;
   double f[2],s[2]; ArraySetAsSeries(f,true); ArraySetAsSeries(s,true);
   if(CopyBuffer(hFastEMA,0,0,2,f)<2) return false;
   if(CopyBuffer(hSlowEMA,0,0,2,s)<2) return false;
   return bullish ? f[1]>s[1] : f[1]<s[1];
}

bool OpenTrade(bool bullish,const FVGZone &z)
{
   double atr=GetATR();
   if(atr<=0) return false;

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0 || bid<=0 || ask<=0) return false;

   double requestedEntry=bullish?ask:bid;
   double sl,tp;

   if(bullish)
   {
      sl=z.low-atr*InpSL_ATR_Buffer;
      double risk=requestedEntry-sl;
      if(risk<=0 || risk>atr*InpMaxSL_ATR) return false;
      tp=requestedEntry+risk*InpRewardRisk;
   }
   else
   {
      sl=z.high+atr*InpSL_ATR_Buffer;
      double risk=sl-requestedEntry;
      if(risk<=0 || risk>atr*InpMaxSL_ATR) return false;
      tp=requestedEntry-risk*InpRewardRisk;
   }

   sl=NormalizePrice(sl);
   tp=NormalizePrice(tp);
   if(!StopsAreValid(requestedEntry,sl,tp,bullish)) return false;

   double rawVolume=0.0, plannedRisk=0.0, effectiveRisk=0.0, effectiveRiskPct=0.0;
   double volume=CalculateVolume(requestedEntry,sl,bullish,rawVolume,plannedRisk,effectiveRisk,effectiveRiskPct);
   if(volume<=0) return false;

   if(!MarginPreflight(bullish,volume,requestedEntry))
   {
      if(InpVerboseLog) Print("FVG212 margin guard rejected entry");
      return false;
   }

   double spreadPoints=(ask-bid)/point;
   bool ok=bullish ? trade.Buy(volume,_Symbol,0,sl,tp,"FVG V2.12 Buy")
                   : trade.Sell(volume,_Symbol,0,sl,tp,"FVG V2.12 Sell");
   if(!ok)
   {
      Print("Trade failed: ",trade.ResultRetcodeDescription());
      return false;
   }

   uint rc=trade.ResultRetcode();
   if(rc!=TRADE_RETCODE_DONE && rc!=TRADE_RETCODE_DONE_PARTIAL && rc!=TRADE_RETCODE_PLACED)
   {
      Print("Trade rejected: ",trade.ResultRetcodeDescription());
      return false;
   }

   g_tradesToday++;
   g_lastEntryTime=TimeCurrent();

   // Build telemetry from actual position fill where possible.
   ulong ticket=GetOurPositionTicket();
   double actualEntry=requestedEntry;
   double actualVolume=volume;
   if(ticket>0 && PositionSelectByTicket(ticket))
   {
      actualEntry=PositionGetDouble(POSITION_PRICE_OPEN);
      actualVolume=PositionGetDouble(POSITION_VOLUME);
   }

   double actualRiskMoney=0.0;
   ENUM_ORDER_TYPE orderType=bullish?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcProfit(orderType,_Symbol,actualVolume,actualEntry,sl,actualRiskMoney))
      actualRiskMoney=-effectiveRisk;
   actualRiskMoney=MathAbs(actualRiskMoney);

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double actualRiskPct=(equity>0.0)?actualRiskMoney/equity*100.0:0.0;
   double slipPts=bullish?(actualEntry-requestedEntry)/point:(requestedEntry-actualEntry)/point;

   g_track.active=true;
   g_track.positionTicket=ticket;
   g_track.positionType=bullish?POSITION_TYPE_BUY:POSITION_TYPE_SELL;
   g_track.entryTime=TimeCurrent();
   g_track.requestedEntry=requestedEntry;
   g_track.actualEntry=actualEntry;
   g_track.initialSL=sl;
   g_track.originalTP=tp;
   g_track.initialRiskPrice=MathAbs(actualEntry-sl);
   g_track.plannedRiskMoney=plannedRisk;
   g_track.effectiveRiskMoney=actualRiskMoney;
   g_track.effectiveRiskPct=actualRiskPct;
   g_track.requestedRawVolume=rawVolume;
   g_track.volume=actualVolume;
   g_track.maxMFE_R=0.0;
   g_track.maxMAE_R=0.0;
   g_track.entrySlippagePoints=slipPts;
   g_track.entrySpreadPoints=spreadPoints;
   g_track.sessionTag=ResearchSessionTag(TimeCurrent());
   g_track.zoneFormed=z.formed;
   g_track.zoneLow=z.low;
   g_track.zoneHigh=z.high;
   g_track.bullishZone=z.bullish;

   if(InpMaxEntrySlippagePoints>0 && slipPts>(double)InpMaxEntrySlippagePoints)
      Print("FVG212 WARNING: entry slippage exceeded configured research threshold: ",DoubleToString(slipPts,1)," pts");

   if(InpVerboseLog)
      Print("FVG212 entry | vol=",DoubleToString(actualVolume,2),
            " risk%=",DoubleToString(actualRiskPct,3),
            " slipPts=",DoubleToString(slipPts,1),
            " session=",g_track.sessionTag);

   return true;
}

//+------------------------------------------------------------------+
//| Position sizing                                                   |
//+------------------------------------------------------------------+
double CalculateVolume(double entry,double sl,bool bullish,
                       double &rawVolume,double &plannedRiskMoney,
                       double &effectiveRiskMoney,double &effectiveRiskPct)
{
   rawVolume=0.0;
   plannedRiskMoney=0.0;
   effectiveRiskMoney=0.0;
   effectiveRiskPct=0.0;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity<=0) return 0;

   double sizingBase = InpAutoCompoundLots ? equity : InpCompoundingBaseBalance;
   if(sizingBase<=0.0) sizingBase=equity;
   plannedRiskMoney=sizingBase*InpRiskPercent/100.0;
   if(plannedRiskMoney<=0) return 0;

   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double brokerMaxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(minLot<=0 || brokerMaxLot<=0 || step<=0) return 0;

   double userMaxLot=(InpMaxLots>0.0)?MathMin(InpMaxLots,brokerMaxLot):brokerMaxLot;

   double lossOneLot=0;
   ENUM_ORDER_TYPE type=bullish?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type,_Symbol,1.0,entry,sl,lossOneLot)) return 0;
   lossOneLot=MathAbs(lossOneLot);
   if(lossOneLot<=0) return 0;

   rawVolume=plannedRiskMoney/lossOneLot;
   double volume=MathFloor(rawVolume/step)*step;
   if(volume<minLot) return 0;
   if(volume>userMaxLot) volume=userMaxLot;
   volume=NormalizeVolume(volume);

   if(volume<=0) return 0;

   double calcLoss=0.0;
   if(!OrderCalcProfit(type,_Symbol,volume,entry,sl,calcLoss)) return 0;
   effectiveRiskMoney=MathAbs(calcLoss);
   effectiveRiskPct=(equity>0.0)?effectiveRiskMoney/equity*100.0:0.0;

   // Hard cap also protects against minimum-lot overshoot and symbol-spec surprises.
   if(InpUseHardRiskCap && effectiveRiskPct > InpMaxEffectiveRiskPct + 1e-8)
   {
      double capMoney=equity*InpMaxEffectiveRiskPct/100.0;
      double cappedVolume=MathFloor((capMoney/lossOneLot)/step)*step;
      if(cappedVolume<minLot) return 0;
      if(cappedVolume>userMaxLot) cappedVolume=userMaxLot;
      volume=NormalizeVolume(cappedVolume);

      if(!OrderCalcProfit(type,_Symbol,volume,entry,sl,calcLoss)) return 0;
      effectiveRiskMoney=MathAbs(calcLoss);
      effectiveRiskPct=effectiveRiskMoney/equity*100.0;
      if(effectiveRiskPct > InpMaxEffectiveRiskPct + 1e-6) return 0;
   }

   return volume;
}

bool MarginPreflight(bool bullish,double volume,double entry)
{
   if(!InpUseMarginGuard) return true;

   ENUM_ORDER_TYPE type=bullish?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double required=0.0;
   if(!OrderCalcMargin(type,_Symbol,volume,entry,required))
      return false;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double currentMargin=AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(equity<=0.0 || freeMargin<=0.0) return false;
   if(required>freeMargin) return false;

   if(InpMaxSingleTradeMarginPct>0.0 && required/equity*100.0 > InpMaxSingleTradeMarginPct)
      return false;

   double projectedMargin=currentMargin+required;
   if(projectedMargin>0.0 && InpMinProjectedMarginLevelPct>0.0)
   {
      double projectedLevel=equity/projectedMargin*100.0;
      if(projectedLevel < InpMinProjectedMarginLevelPct)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Position management                                               |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   if(!HasOurPosition()) return;
   ulong ticket=GetOurPositionTicket();
   if(ticket==0 || !PositionSelectByTicket(ticket)) return;

   long type=PositionGetInteger(POSITION_TYPE);
   double open=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl=PositionGetDouble(POSITION_SL);
   double tp=PositionGetDouble(POSITION_TP);
   double price=(type==POSITION_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(open<=0 || price<=0 || tp<=0 || InpRewardRisk<=0) return;

   // TP remains unchanged from initial placement, so it can reconstruct original R.
   double initialRisk=MathAbs(tp-open)/InpRewardRisk;
   if(initialRisk<=0) return;
   double profitDist=(type==POSITION_TYPE_BUY)?price-open:open-price;
   double rr=profitDist/initialRisk;
   if(rr<=0) return;

   if(InpUseProfitLock)
   {
      double lockRR=-1;
      if(rr>=InpLock2TriggerRR) lockRR=InpLock2RR;
      else if(rr>=InpLock1TriggerRR) lockRR=InpLock1RR;

      if(lockRR>=0)
      {
         double newSL=(type==POSITION_TYPE_BUY)?open+initialRisk*lockRR:open-initialRisk*lockRR;
         newSL=NormalizePrice(newSL);
         if(IsBetterSL(type,sl,newSL) && StopsAreValid(price,newSL,tp,type==POSITION_TYPE_BUY))
            SafeModifyPosition(ticket,newSL,tp,"LOCK");
      }
   }

   if(InpUseATRTrail && rr>=InpTrailStartRR)
   {
      double atr=GetATR();
      if(atr<=0) return;
      double newSL=(type==POSITION_TYPE_BUY)?price-atr*InpTrail_ATR:price+atr*InpTrail_ATR;
      double floorSL=(type==POSITION_TYPE_BUY)?open+initialRisk*InpLock2RR:open-initialRisk*InpLock2RR;
      if(type==POSITION_TYPE_BUY) newSL=MathMax(newSL,floorSL);
      else newSL=MathMin(newSL,floorSL);
      newSL=NormalizePrice(newSL);
      if(IsBetterSL(type,sl,newSL) && StopsAreValid(price,newSL,tp,type==POSITION_TYPE_BUY))
         SafeModifyPosition(ticket,newSL,tp,"TRAIL");
   }
}

bool SafeModifyPosition(ulong ticket,double newSL,double tp,string reason)
{
   ResetLastError();
   bool ok=trade.PositionModify(ticket,newSL,tp);
   uint rc=trade.ResultRetcode();
   if(!ok || (rc!=TRADE_RETCODE_DONE && rc!=TRADE_RETCODE_NO_CHANGES && rc!=TRADE_RETCODE_PLACED))
   {
      Print("FVG212 SL modify failed [",reason,"] ticket=",ticket,
            " sl=",DoubleToString(newSL,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS)),
            " rc=",rc," ",trade.ResultRetcodeDescription()," err=",GetLastError());
      return false;
   }
   return true;
}

bool StopsAreValid(double price,double sl,double tp,bool bullish)
{
   double p=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(p<=0) return false;
   long st=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long fr=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist=MathMax(st,fr)*p;
   if(bullish)
      return sl<price && tp>price && price-sl>=minDist && tp-price>=minDist;
   return sl>price && tp<price && sl-price>=minDist && price-tp>=minDist;
}

bool IsBetterSL(long type,double oldSL,double newSL)
{
   if(type==POSITION_TYPE_BUY) return oldSL==0 || newSL>oldSL;
   return oldSL==0 || newSL<oldSL;
}

//+------------------------------------------------------------------+
//| Telemetry                                                         |
//+------------------------------------------------------------------+
void ResetTelemetry()
{
   g_track.active=false;
   g_track.positionTicket=0;
   g_track.positionType=-1;
   g_track.entryTime=0;
   g_track.requestedEntry=0.0;
   g_track.actualEntry=0.0;
   g_track.initialSL=0.0;
   g_track.originalTP=0.0;
   g_track.initialRiskPrice=0.0;
   g_track.plannedRiskMoney=0.0;
   g_track.effectiveRiskMoney=0.0;
   g_track.effectiveRiskPct=0.0;
   g_track.requestedRawVolume=0.0;
   g_track.volume=0.0;
   g_track.maxMFE_R=0.0;
   g_track.maxMAE_R=0.0;
   g_track.entrySlippagePoints=0.0;
   g_track.entrySpreadPoints=0.0;
   g_track.sessionTag="";
   g_track.zoneFormed=0;
   g_track.zoneLow=0.0;
   g_track.zoneHigh=0.0;
   g_track.bullishZone=false;
}

void UpdateTelemetryExcursions()
{
   if(!g_track.active || g_track.initialRiskPrice<=0.0) return;
   if(!HasOurPosition()) return;

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(bid<=0 || ask<=0) return;

   double price=(g_track.positionType==POSITION_TYPE_BUY)?bid:ask;
   double move=(g_track.positionType==POSITION_TYPE_BUY)?price-g_track.actualEntry:g_track.actualEntry-price;
   double r=move/g_track.initialRiskPrice;
   if(r>g_track.maxMFE_R) g_track.maxMFE_R=r;
   if(r<0.0 && -r>g_track.maxMAE_R) g_track.maxMAE_R=-r;
}

void RestoreTelemetryFromPosition()
{
   if(!HasOurPosition()) return;
   ulong ticket=GetOurPositionTicket();
   if(ticket==0 || !PositionSelectByTicket(ticket)) return;

   long type=PositionGetInteger(POSITION_TYPE);
   double open=PositionGetDouble(POSITION_PRICE_OPEN);
   double tp=PositionGetDouble(POSITION_TP);
   double currentSL=PositionGetDouble(POSITION_SL);
   double volume=PositionGetDouble(POSITION_VOLUME);
   datetime t=(datetime)PositionGetInteger(POSITION_TIME);
   if(open<=0 || tp<=0 || InpRewardRisk<=0) return;

   double initialRisk=MathAbs(tp-open)/InpRewardRisk;
   if(initialRisk<=0) return;
   double reconstructedSL=(type==POSITION_TYPE_BUY)?open-initialRisk:open+initialRisk;

   double riskMoney=0.0;
   ENUM_ORDER_TYPE ot=(type==POSITION_TYPE_BUY)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcProfit(ot,_Symbol,volume,open,reconstructedSL,riskMoney)) return;
   riskMoney=MathAbs(riskMoney);

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_track.active=true;
   g_track.positionTicket=ticket;
   g_track.positionType=type;
   g_track.entryTime=t;
   g_track.requestedEntry=open;
   g_track.actualEntry=open;
   g_track.initialSL=reconstructedSL;
   g_track.originalTP=tp;
   g_track.initialRiskPrice=initialRisk;
   g_track.plannedRiskMoney=riskMoney;
   g_track.effectiveRiskMoney=riskMoney;
   g_track.effectiveRiskPct=(equity>0.0)?riskMoney/equity*100.0:0.0;
   g_track.requestedRawVolume=volume;
   g_track.volume=volume;
   g_track.maxMFE_R=0.0;
   g_track.maxMAE_R=0.0;
   g_track.entrySlippagePoints=0.0;
   g_track.entrySpreadPoints=0.0;
   g_track.sessionTag=ResearchSessionTag(t);
   g_track.zoneFormed=g_zone.formed;
   g_track.zoneLow=g_zone.low;
   g_track.zoneHigh=g_zone.high;
   g_track.bullishZone=g_zone.bullish;

   if(InpVerboseLog)
      Print("FVG212 telemetry restored for open position ticket=",ticket," currentSL=",currentSL);
}

void EnsureTelemetryHeader()
{
   int h=FileOpen(InpTelemetryFile,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(h==INVALID_HANDLE)
   {
      Print("FVG212 telemetry open failed: ",GetLastError());
      return;
   }

   if(FileSize(h)==0)
   {
      FileWrite(h,
         "symbol","magic","entry_time","exit_time","direction","session",
         "zone_formed","zone_low","zone_high","requested_entry","actual_entry",
         "initial_sl","original_tp","initial_risk_price","requested_raw_volume","volume",
         "planned_risk_money","effective_risk_money","effective_risk_pct",
         "entry_spread_points","entry_slippage_points","mfe_r","mae_r",
         "exit_price","net_profit","realized_r","exit_deal");
   }
   FileClose(h);
}

void WriteTelemetryRow(datetime closeTime,double closePrice,double net,double realizedR,ulong deal)
{
   if(!InpEnableTelemetry) return;

   int h=FileOpen(InpTelemetryFile,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(h==INVALID_HANDLE)
   {
      Print("FVG212 telemetry write failed: ",GetLastError());
      return;
   }
   FileSeek(h,0,SEEK_END);

   string direction=(g_track.positionType==POSITION_TYPE_BUY)?"BUY":"SELL";
   FileWrite(h,
      _Symbol,(long)InpMagic,
      TimeToString(g_track.entryTime,TIME_DATE|TIME_SECONDS),
      TimeToString(closeTime,TIME_DATE|TIME_SECONDS),
      direction,g_track.sessionTag,
      TimeToString(g_track.zoneFormed,TIME_DATE|TIME_SECONDS),
      DoubleToString(g_track.zoneLow,_Digits),DoubleToString(g_track.zoneHigh,_Digits),
      DoubleToString(g_track.requestedEntry,_Digits),DoubleToString(g_track.actualEntry,_Digits),
      DoubleToString(g_track.initialSL,_Digits),DoubleToString(g_track.originalTP,_Digits),
      DoubleToString(g_track.initialRiskPrice,_Digits),
      DoubleToString(g_track.requestedRawVolume,4),DoubleToString(g_track.volume,4),
      DoubleToString(g_track.plannedRiskMoney,2),DoubleToString(g_track.effectiveRiskMoney,2),
      DoubleToString(g_track.effectiveRiskPct,4),
      DoubleToString(g_track.entrySpreadPoints,1),DoubleToString(g_track.entrySlippagePoints,1),
      DoubleToString(g_track.maxMFE_R,4),DoubleToString(g_track.maxMAE_R,4),
      DoubleToString(closePrice,_Digits),DoubleToString(net,2),DoubleToString(realizedR,4),(long)deal);

   FileClose(h);
}

string ResearchSessionTag(datetime t)
{
   MqlDateTime dt; TimeToStruct(t,dt);
   int h=dt.hour+InpResearchSessionOffsetHours;
   while(h<0) h+=24;
   while(h>=24) h-=24;

   if(h>=0 && h<7) return "ASIA";
   if(h>=7 && h<12) return "LONDON";
   if(h>=12 && h<16) return "LONDON_NY_OVERLAP";
   if(h>=16 && h<21) return "NEW_YORK";
   return "OTHER";
}

//+------------------------------------------------------------------+
//| Trading permissions / daily controls                              |
//+------------------------------------------------------------------+
bool TradingAllowed()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;
   if(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL) return false;

   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   bool s1=InpUseSession1 && HourInWindow(dt.hour,InpSession1Start,InpSession1End);
   bool s2=InpUseSession2 && HourInWindow(dt.hour,InpSession2Start,InpSession2End);
   if(!s1 && !s2) return false;

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double p=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(bid<=0 || ask<=0 || p<=0) return false;
   if((ask-bid)/p > InpMaxSpreadPoints) return false;

   if(InpDailyLossPct>0 && g_dayStartEquity>0)
   {
      double eq=AccountInfoDouble(ACCOUNT_EQUITY);
      if((g_dayStartEquity-eq)/g_dayStartEquity*100.0 >= InpDailyLossPct)
         return false;
   }
   return true;
}

bool HourInWindow(int h,int start,int end)
{
   if(start==end) return true; // preserves V2.11 semantics: 0->0 means all day
   if(start<end) return h>=start && h<end;
   return h>=start || h<end;
}

void ResetDailyStats()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   g_dayKey=dt.year*1000+dt.day_of_year;
   g_tradesToday=CountTodayEntries();

   string keyDay=GVPrefix()+"DAYKEY";
   string keyEq=GVPrefix()+"DAYEQ";
   if(InpPersistState && GlobalVariableCheck(keyDay) && GlobalVariableCheck(keyEq) &&
      (int)GlobalVariableGet(keyDay)==g_dayKey)
   {
      g_dayStartEquity=GlobalVariableGet(keyEq);
   }
   else
   {
      g_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      if(InpPersistState)
      {
         GlobalVariableSet(keyDay,(double)g_dayKey);
         GlobalVariableSet(keyEq,g_dayStartEquity);
      }
   }
}

void ResetDailyStatsIfNeeded()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int key=dt.year*1000+dt.day_of_year;
   if(key!=g_dayKey) ResetDailyStats();
}

int CountTodayEntries()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   dt.hour=0;dt.min=0;dt.sec=0;
   datetime from=StructToTime(dt),to=TimeCurrent();
   if(!HistorySelect(from,to)) return 0;

   int count=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong d=HistoryDealGetTicket(i); if(d==0) continue;
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol) continue;
      if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY)==DEAL_ENTRY_IN) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Persistent zone state                                             |
//+------------------------------------------------------------------+
void PersistZoneIfNeeded()
{
   if(InpPersistState) SaveZoneState();
}

void SaveZoneState()
{
   string p=GVPrefix();
   GlobalVariableSet(p+"Z_VALID",g_zone.valid?1.0:0.0);
   GlobalVariableSet(p+"Z_BULL",g_zone.bullish?1.0:0.0);
   GlobalVariableSet(p+"Z_LOW",g_zone.low);
   GlobalVariableSet(p+"Z_HIGH",g_zone.high);
   GlobalVariableSet(p+"Z_FORMED",(double)g_zone.formed);
   GlobalVariableSet(p+"Z_TRADED",g_zone.traded?1.0:0.0);
}

void LoadZoneState()
{
   string p=GVPrefix();
   if(!GlobalVariableCheck(p+"Z_VALID")) return;

   g_zone.valid=GlobalVariableGet(p+"Z_VALID")>0.5;
   g_zone.bullish=GlobalVariableCheck(p+"Z_BULL") && GlobalVariableGet(p+"Z_BULL")>0.5;
   g_zone.low=GlobalVariableCheck(p+"Z_LOW")?GlobalVariableGet(p+"Z_LOW"):0.0;
   g_zone.high=GlobalVariableCheck(p+"Z_HIGH")?GlobalVariableGet(p+"Z_HIGH"):0.0;
   g_zone.formed=GlobalVariableCheck(p+"Z_FORMED")?(datetime)GlobalVariableGet(p+"Z_FORMED"):0;
   g_zone.traded=GlobalVariableCheck(p+"Z_TRADED") && GlobalVariableGet(p+"Z_TRADED")>0.5;
   g_zone.shift=(g_zone.formed>0)?iBarShift(_Symbol,InpEntryTF,g_zone.formed,false):-1;
