//+------------------------------------------------------------------+
//| AUREON_PRIME_MT5_V4_MULTI_ASSET.mq5                              |
//| One MT5 terminal. Gold 24/5 + Bitcoin 24/7.                       |
//| Timer-driven dual-symbol execution and shared portfolio governor.  |
//+------------------------------------------------------------------+
#property strict
#property version   "4.10"
#property description "AUREON PRIME V4.10: single-terminal Gold/Bitcoin demo-forward engine with PrimeXBT-safe BTCUSDT risk fallback, server OrderCheck preflight, shared portfolio risk, MTF FVG intelligence and adaptive management."

#include <Trade/Trade.mqh>
CTrade trade;

enum ENUM_AUREON_KIND
{
   AUREON_KIND_NONE = 0,
   AUREON_KIND_GOLD = 1,
   AUREON_KIND_BITCOIN = 2
};

struct FVGZone
{
   bool valid;
   bool bullish;
   double low;
   double high;
   datetime formed;
   int attempts;
   datetime lastExitTime;
   double lastRealizedR;
   double lastRiskMoney;
   double gapATR;
   double bodyATR;
   double bodyRatio;
   double riskSpentPct;
   bool quarantined;
};

struct AssetState
{
   bool enabled;
   int kind;
   string symbol;
   ulong magic;

   ENUM_TIMEFRAMES entryTF;
   ENUM_TIMEFRAMES regimeTF;
   ENUM_TIMEFRAMES contextTF1;
   ENUM_TIMEFRAMES contextTF2;
   ENUM_TIMEFRAMES contextTF3;

   int hATR;
   int hRegimeFast;
   int hRegimeSlow;
   int hADX;
   int hTF1Fast;
   int hTF1Slow;
   int hTF2Fast;
   int hTF2Slow;
   int hTF3Fast;
   int hTF3Slow;

   datetime lastBar;
   long lastSpreadTickMsc;
   double spreadEMA;
   int spreadSamples;

   int mtfScore;
   double qualityScore;
   double atrRatio;
   double shockRangeATR;
   double spreadRatio;
   double regimeFast;
   double regimeSlow;
   double regimeSlope;
   double regimeADX;

   FVGZone zone;
};

//--------------------------- Core safety ------------------------------
input group "AUREON Core Safety"
input bool InpExecutionArmed = false;
input bool InpDemoOnly = true;
input bool InpEnableGold = true;
input bool InpEnableBitcoin = true;
input string InpGoldSymbol = "";
input string InpBitcoinSymbol = "";
input ulong InpMagicBase = 26094000;
input int InpTimerSeconds = 1;
input int InpDeviationPoints = 30;
input bool InpOnePositionPerSymbol = true;
input int InpPortfolioMaxOpenPositions = 2;
input double InpPortfolioDailyLossPct = 2.0;
input double InpPortfolioDDStage1Pct = 3.0;
input double InpPortfolioDDStage1Scale = 0.70;
input double InpPortfolioDDStage2Pct = 5.0;
input double InpPortfolioDDStage2Scale = 0.45;
input double InpPortfolioHardStopDDPct = 8.0;
input double InpMinProjectedMarginLevelPct = 175.0;
input double InpMaxSingleTradeMarginPct = 25.0;
input int InpMaxTickAgeSeconds = 120;
input double InpMaxSpreadATRRatio = 0.08;

//--------------------------- Gold profile -----------------------------
input group "Gold Profile"
input ENUM_TIMEFRAMES InpGoldEntryTF = PERIOD_M1;
input ENUM_TIMEFRAMES InpGoldRegimeTF = PERIOD_M15;
input double InpGoldRiskPct = 0.50;
input double InpGoldLongRiskScale = 0.75;
input double InpGoldShortRiskScale = 1.00;
input double InpGoldMinLongQuality = 58.0;
input double InpGoldMinShortQuality = 48.0;
input int InpGoldLongMinAlignedVotes = 1;
input int InpGoldShortMinAlignedVotes = 0;
input int InpGoldMaxAttemptsPerFVG = 2;
input int InpGoldMaxTradesDay = 12;
input double InpGoldRewardRisk = 30.0;
input int InpGoldMaxSpreadPoints = 80;

//--------------------------- Bitcoin profile --------------------------
input group "Bitcoin Profile"
input ENUM_TIMEFRAMES InpBitcoinEntryTF = PERIOD_M5;
input ENUM_TIMEFRAMES InpBitcoinRegimeTF = PERIOD_H1;
input double InpBitcoinRiskPct = 0.35;
input double InpBitcoinLongRiskScale = 1.00;
input double InpBitcoinShortRiskScale = 0.90;
input double InpBitcoinMinLongQuality = 55.0;
input double InpBitcoinMinShortQuality = 55.0;
input int InpBitcoinLongMinAlignedVotes = 1;
input int InpBitcoinShortMinAlignedVotes = 1;
input int InpBitcoinMaxAttemptsPerFVG = 2;
input int InpBitcoinMaxTradesDay = 18;
input double InpBitcoinRewardRisk = 15.0;
input int InpBitcoinMaxSpreadPoints = 0;
input bool InpBitcoinAllowWeekend = true;
input bool InpUseBitcoinManualRiskFallback = true;
input double InpBitcoinUSTUSDConversion = 1.0;
input double InpBitcoinFallbackRiskSafetyMultiplier = 1.05;
input bool InpRequireBitcoinServerOrderCheck = true;

//--------------------------- Signal model -----------------------------
input group "FVG / Displacement"
input int InpATRPeriod = 14;
input double InpMinFVG_ATR = 0.15;
input double InpMinBody_ATR = 0.50;
input double InpMinBodyRatio = 0.60;
input int InpMaxFVG_Bars = 700;
input bool InpReplaceWithNewFVG = true;
input bool InpRequireRejection = true;
input bool InpRequireMidpoint = false;
input double InpSL_ATR_Buffer = 0.15;
input double InpMaxSL_ATR = 3.0;

input group "MTF / Market Quality"
input int InpFastEMA = 20;
input int InpSlowEMA = 50;
input int InpADXPeriod = 14;
input double InpMinADX = 18.0;
input int InpVolatilityLookback = 50;
input double InpMinATRRatio = 0.35;
input double InpMaxATRRatio = 1.90;
input bool InpUseShockGuard = true;
input double InpMaxClosedBarRangeATR = 2.50;
input int InpShockCooldownBars = 2;
input bool InpUseRelativeSpreadGuard = true;
input double InpRelativeSpreadMultiplier = 3.0;
input int InpSpreadEMAWarmupTicks = 150;

input group "Controlled Re-entry"
input bool InpUseControlledReentry = true;
input int InpReentryCooldownBars = 3;
input bool InpRequireClosedBarRejectionOnReentry = true;
input double InpReentryCloseThreshold = 0.60;
input bool InpAllowReentryAfterProfit = false;
input double InpQuarantineLossR = 1.50;
input double InpSecondAttemptRiskScale = 0.65;
input double InpMaxZoneRiskBudgetPct = 1.20;

input group "Position Management"
input bool InpUseProfitLock = true;
input double InpLock1TriggerRR = 0.50;
input double InpLock1RR = 0.10;
input double InpLock2TriggerRR = 1.00;
input double InpLock2RR = 0.35;
input bool InpUseSmartTrail = true;
input double InpTrailStartRR = 2.00;
input double InpTrailATR = 0.30;
input double InpTrailTightenRR = 5.00;
input double InpTrailTightATR = 0.20;
input double InpTrailFloorRR = 0.50;

input group "Telemetry / State"
input bool InpPersistState = true;
input bool InpEnableTelemetry = true;
input string InpTelemetryFile = "AUREON_PRIME_MT5_V4.csv";
input bool InpVerboseLog = false;

AssetState g_assets[2];

//+------------------------------------------------------------------+
//| Lifecycle                                                         |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   bool any=false;

   if(InpEnableGold)
   {
      string symbol=ResolveSymbol(AUREON_KIND_GOLD,InpGoldSymbol);
      if(symbol!="")
      {
         if(InitAsset(g_assets[0],AUREON_KIND_GOLD,symbol))
            any=true;
         else
            Print("AUREON V4: Gold engine failed to initialise for ",symbol);
      }
      else
         Print("AUREON V4: no Gold/XAU symbol discovered.");
   }

   if(InpEnableBitcoin)
   {
      string symbol=ResolveSymbol(AUREON_KIND_BITCOIN,InpBitcoinSymbol);
      if(symbol!="")
      {
         if(InitAsset(g_assets[1],AUREON_KIND_BITCOIN,symbol))
            any=true;
         else
            Print("AUREON V4: Bitcoin engine failed to initialise for ",symbol);
      }
      else
         Print("AUREON V4: no BTC symbol discovered.");
   }

   if(!any)
      return INIT_FAILED;

   EnsurePortfolioState();

   if(InpEnableTelemetry)
      EnsureTelemetryHeader();

   EventSetTimer(InpTimerSeconds);

   Print("AUREON PRIME MT5 V4.00 started | armed=",InpExecutionArmed,
         " demoOnly=",InpDemoOnly,
         " Gold=",g_assets[0].enabled?g_assets[0].symbol:"DISABLED",
         " BTC=",g_assets[1].enabled?g_assets[1].symbol:"DISABLED");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();

   for(int i=0;i<ArraySize(g_assets);i++)
   {
      if(!g_assets[i].enabled) continue;
      PersistZone(g_assets[i]);
      ReleaseAsset(g_assets[i]);
   }
}

void OnTick()
{
   // Deliberately empty. V4 is timer-driven so BTC continues to be evaluated
   // even when the chart symbol (for example Gold) is not producing ticks.
}

void OnTimer()
{
   EnsurePortfolioState();
   UpdatePortfolioPeak();

   for(int i=0;i<ArraySize(g_assets);i++)
   {
      if(g_assets[i].enabled)
         ProcessAsset(g_assets[i]);
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   string sym=HistoryDealGetString(trans.deal,DEAL_SYMBOL);
   ulong magic=(ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
   int idx=FindAssetIndex(sym,magic);
   if(idx<0) return;

   ENUM_DEAL_ENTRY entryType=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entryType!=DEAL_ENTRY_OUT && entryType!=DEAL_ENTRY_OUT_BY)
      return;

   double net=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)
             +HistoryDealGetDouble(trans.deal,DEAL_COMMISSION)
             +HistoryDealGetDouble(trans.deal,DEAL_SWAP)
             +HistoryDealGetDouble(trans.deal,DEAL_FEE);

   RegisterExit(g_assets[idx],trans.deal,net);
}

void RegisterExit(AssetState &a,ulong deal,double net)
{
   double realizedR=(a.zone.lastRiskMoney>0.0)?net/a.zone.lastRiskMoney:0.0;
   a.zone.lastExitTime=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
   a.zone.lastRealizedR=realizedR;

   if(realizedR<=-InpQuarantineLossR || a.zone.attempts>=MaxAttempts(a))
      a.zone.quarantined=true;

   PersistZone(a);
   WriteTelemetry(a,"EXIT",realizedR,net,0.0,0.0);

   if(InpVerboseLog)
      Print("AUREON V4 exit | ",a.symbol," R=",DoubleToString(realizedR,3),
            " net=",DoubleToString(net,2)," attempt=",a.zone.attempts);
}

//+------------------------------------------------------------------+
//| Asset initialization                                              |
//+------------------------------------------------------------------+
bool InitAsset(AssetState &a,int kind,string symbol)
{
   a.enabled=false;
   a.kind=kind;
   a.symbol=symbol;
   a.magic=InpMagicBase+(ulong)kind;
   a.entryTF=(kind==AUREON_KIND_GOLD)?InpGoldEntryTF:InpBitcoinEntryTF;
   a.regimeTF=(kind==AUREON_KIND_GOLD)?InpGoldRegimeTF:InpBitcoinRegimeTF;
   a.contextTF1=(kind==AUREON_KIND_GOLD)?PERIOD_M5:PERIOD_M15;
   a.contextTF2=(kind==AUREON_KIND_GOLD)?PERIOD_M15:PERIOD_H1;
   a.contextTF3=(kind==AUREON_KIND_GOLD)?PERIOD_H1:PERIOD_H4;
   a.lastBar=0;
   a.lastSpreadTickMsc=0;
   a.spreadEMA=0.0;
   a.spreadSamples=0;
   a.mtfScore=0;
   a.qualityScore=0.0;
   a.atrRatio=0.0;
   a.shockRangeATR=0.0;
   a.spreadRatio=1.0;
   a.regimeFast=0.0;
   a.regimeSlow=0.0;
   a.regimeSlope=0.0;
   a.regimeADX=0.0;

   ResetZone(a.zone);

   if(!SymbolSelect(symbol,true))
      return false;

   a.hATR=iATR(symbol,a.entryTF,InpATRPeriod);
   a.hRegimeFast=iMA(symbol,a.regimeTF,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   a.hRegimeSlow=iMA(symbol,a.regimeTF,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   a.hADX=iADX(symbol,a.regimeTF,InpADXPeriod);

   a.hTF1Fast=iMA(symbol,a.contextTF1,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   a.hTF1Slow=iMA(symbol,a.contextTF1,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   a.hTF2Fast=iMA(symbol,a.contextTF2,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   a.hTF2Slow=iMA(symbol,a.contextTF2,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);
   a.hTF3Fast=iMA(symbol,a.contextTF3,InpFastEMA,0,MODE_EMA,PRICE_CLOSE);
   a.hTF3Slow=iMA(symbol,a.contextTF3,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE);

   if(a.hATR==INVALID_HANDLE || a.hRegimeFast==INVALID_HANDLE || a.hRegimeSlow==INVALID_HANDLE ||
      a.hADX==INVALID_HANDLE || a.hTF1Fast==INVALID_HANDLE || a.hTF1Slow==INVALID_HANDLE ||
      a.hTF2Fast==INVALID_HANDLE || a.hTF2Slow==INVALID_HANDLE ||
      a.hTF3Fast==INVALID_HANDLE || a.hTF3Slow==INVALID_HANDLE)
   {
      ReleaseAsset(a);
      return false;
   }

   a.enabled=true;

   if(InpPersistState)
      LoadZoneState(a);

   Print("AUREON V4 asset online | ",AssetName(a)," symbol=",a.symbol,
         " magic=",(long)a.magic," entryTF=",EnumToString(a.entryTF),
         " regimeTF=",EnumToString(a.regimeTF));

   return true;
}

void ReleaseAsset(AssetState &a)
{
   ReleaseHandle(a.hATR);
   ReleaseHandle(a.hRegimeFast);
   ReleaseHandle(a.hRegimeSlow);
   ReleaseHandle(a.hADX);
   ReleaseHandle(a.hTF1Fast);
   ReleaseHandle(a.hTF1Slow);
   ReleaseHandle(a.hTF2Fast);
   ReleaseHandle(a.hTF2Slow);
   ReleaseHandle(a.hTF3Fast);
   ReleaseHandle(a.hTF3Slow);
}

void ResetZone(FVGZone &z)
{
   z.valid=false;
   z.bullish=false;
   z.low=0.0;
   z.high=0.0;
   z.formed=0;
   z.attempts=0;
   z.lastExitTime=0;
   z.lastRealizedR=0.0;
   z.lastRiskMoney=0.0;
   z.gapATR=0.0;
   z.bodyATR=0.0;
   z.bodyRatio=0.0;
   z.riskSpentPct=0.0;
   z.quarantined=false;
}

//+------------------------------------------------------------------+
//| Process loop                                                      |
//+------------------------------------------------------------------+
void ProcessAsset(AssetState &a)
{
   UpdateSpreadState(a);
   ManageOpenPosition(a);

   if(IsNewBar(a))
      UpdateFVG(a);

   if(!TradingAllowed(a)) return;
   if(InpOnePositionPerSymbol && HasOurPosition(a)) return;
   if(CountOpenPositionsAll()>=InpPortfolioMaxOpenPositions) return;
   if(CountTodayEntries(a)>=MaxTradesDay(a)) return;

   if(!a.zone.valid || a.zone.quarantined) return;

   if(!ZoneStillValid(a))
   {
      a.zone.valid=false;
      PersistZone(a);
      return;
   }

   if(!RefreshContext(a,a.zone.bullish)) return;

   a.qualityScore=ComputeEntryQualityScore(a,a.zone.bullish);
   if(!DirectionalQualityAllows(a,a.zone.bullish)) return;
   if(!ReentryAllows(a,a.zone.bullish)) return;

   TryFVGEntry(a);
}

//+------------------------------------------------------------------+
//| Symbol discovery                                                  |
//+------------------------------------------------------------------+
string ResolveSymbol(int kind,string configured)
{
   if(StringLen(configured)>0)
   {
      if(!SymbolSelect(configured,true))
      {
         Print("AUREON V4 configured symbol unavailable: ",configured);
         return "";
      }

      long configuredMode=SymbolInfoInteger(configured,SYMBOL_TRADE_MODE);
      if(configuredMode!=SYMBOL_TRADE_MODE_FULL)
      {
         Print("AUREON V4 configured symbol is not fully tradable: ",configured,
               " tradeMode=",configuredMode);
         return "";
      }

      return configured;
   }

   string best="";
   int bestScore=-1;
   int total=SymbolsTotal(false);

   for(int i=0;i<total;i++)
   {
      string sym=SymbolName(i,false);
      string up=sym;
      StringToUpper(up);

      bool relevant=false;
      int score=0;

      if(kind==AUREON_KIND_GOLD)
      {
         relevant=(StringFind(up,"XAU")>=0 || StringFind(up,"GOLD")>=0);
         if(!relevant) continue;

         if(up=="XAUUSD") score=100;
         else if(up=="GOLD") score=95;
         else if(StringFind(up,"XAUUSD")>=0) score=90;
         else if(StringFind(up,"GOLD")>=0) score=80;
         else score=50;
      }
      else
      {
         relevant=(StringFind(up,"BTC")>=0);
         if(!relevant) continue;

         if(up=="BTCUSD") score=100;
         else if(up=="BTCUSDT") score=95;
         else if(StringFind(up,"BTCUSD")>=0) score=90;
         else if(StringFind(up,"BTCUSDT")>=0) score=85;
         else score=50;
      }

      long tradeMode=SymbolInfoInteger(sym,SYMBOL_TRADE_MODE);

      // Never select a disabled/close-only broker symbol merely because its
      // name looks canonical. PrimeXBT exposes BTCUSD in the catalogue while
      // BTCUSDT is the fully tradable Bitcoin CFD on the validated demo server.
      if(tradeMode!=SYMBOL_TRADE_MODE_FULL)
         continue;

      score+=100;

      if(score>bestScore)
      {
         bestScore=score;
         best=sym;
      }
   }

   if(best!="" && !SymbolSelect(best,true))
      return "";

   return best;
}

int FindAssetIndex(string symbol,ulong magic)
{
   for(int i=0;i<ArraySize(g_assets);i++)
   {
      if(!g_assets[i].enabled) continue;
      if(g_assets[i].symbol==symbol && g_assets[i].magic==magic)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| FVG discovery                                                     |
//+------------------------------------------------------------------+
void UpdateFVG(AssetState &a)
{
   FVGZone newest;
   ResetZone(newest);

   if(!FindNewestFVG(a,newest))
      return;

   bool replace=!a.zone.valid || FVGExpired(a,a.zone) ||
                (InpReplaceWithNewFVG && newest.formed>a.zone.formed);

   if(replace)
   {
      a.zone=newest;
      PersistZone(a);

      if(InpVerboseLog)
         Print("AUREON V4 zone | ",a.symbol," ",a.zone.bullish?"BULL":"BEAR",
               " low=",DoubleToString(a.zone.low,(int)SymbolInfoInteger(a.symbol,SYMBOL_DIGITS)),
               " high=",DoubleToString(a.zone.high,(int)SymbolInfoInteger(a.symbol,SYMBOL_DIGITS)),
               " gapATR=",DoubleToString(a.zone.gapATR,3));
   }
}

bool FindNewestFVG(AssetState &a,FVGZone &z)
{
   MqlRates r[];
   double atr[];
   ArraySetAsSeries(r,true);
   ArraySetAsSeries(atr,true);

   int need=InpMaxFVG_Bars+5;
   if(need<30) need=30;

   if(CopyRates(a.symbol,a.entryTF,0,need,r)<6) return false;
   if(CopyBuffer(a.hATR,0,0,need,atr)<6) return false;

   for(int s=1; s<=InpMaxFVG_Bars && s+2<ArraySize(r); s++)
   {
      double av=atr[s];
      if(av<=0.0) continue;

      double oldHigh=r[s+2].high;
      double oldLow=r[s+2].low;
      double mo=r[s+1].open;
      double mc=r[s+1].close;
      double mh=r[s+1].high;
      double ml=r[s+1].low;
      double newHigh=r[s].high;
      double newLow=r[s].low;

      double body=MathAbs(mc-mo);
      double range=mh-ml;
      if(range<=0.0) continue;
      if(body<av*InpMinBody_ATR || body/range<InpMinBodyRatio) continue;

      if(oldHigh<newLow && mc>mo)
      {
         double gap=newLow-oldHigh;
         if(gap>=av*InpMinFVG_ATR)
         {
            z.valid=true;
            z.bullish=true;
            z.low=oldHigh;
            z.high=newLow;
            z.formed=r[s].time;
            z.gapATR=gap/av;
            z.bodyATR=body/av;
            z.bodyRatio=body/range;
            return true;
         }
      }

      if(oldLow>newHigh && mc<mo)
      {
         double gap=oldLow-newHigh;
         if(gap>=av*InpMinFVG_ATR)
         {
            z.valid=true;
            z.bullish=false;
            z.low=newHigh;
            z.high=oldLow;
            z.formed=r[s].time;
            z.gapATR=gap/av;
            z.bodyATR=body/av;
            z.bodyRatio=body/range;
            return true;
         }
      }
   }

   return false;
}

bool ZoneStillValid(AssetState &a)
{
   if(!a.zone.valid || FVGExpired(a,a.zone))
      return false;

   MqlRates r[];
   ArraySetAsSeries(r,true);
   if(CopyRates(a.symbol,a.entryTF,0,3,r)<3)
      return false;

   double c=r[1].close;
   if(a.zone.bullish && c<a.zone.low) return false;
   if(!a.zone.bullish && c>a.zone.high) return false;
   return true;
}

bool FVGExpired(AssetState &a,const FVGZone &z)
{
   if(!z.valid) return true;
   int shift=iBarShift(a.symbol,a.entryTF,z.formed,false);
   return shift<0 || shift>InpMaxFVG_Bars;
}

//+------------------------------------------------------------------+
//| Context                                                           |
//+------------------------------------------------------------------+
bool RefreshContext(AssetState &a,bool bullish)
{
   if(!ReadRegime(a)) return false;

   int v1=ReadTrendVote(a.hTF1Fast,a.hTF1Slow);
   int v2=ReadTrendVote(a.hTF2Fast,a.hTF2Slow);
   int v3=ReadTrendVote(a.hTF3Fast,a.hTF3Slow);
   a.mtfScore=v1+v2+v3;

   if(!ReadMarketQuality(a)) return false;
   return true;
}

bool ReadRegime(AssetState &a)
{
   double f[],s[],adx[];
   ArrayResize(f,3); ArrayResize(s,3); ArrayResize(adx,2);
   ArraySetAsSeries(f,true); ArraySetAsSeries(s,true); ArraySetAsSeries(adx,true);

   if(CopyBuffer(a.hRegimeFast,0,0,3,f)<3) return false;
   if(CopyBuffer(a.hRegimeSlow,0,0,3,s)<3) return false;
   if(CopyBuffer(a.hADX,0,0,2,adx)<2) return false;

   a.regimeFast=f[1];
   a.regimeSlow=s[1];
   a.regimeSlope=f[1]-f[2];
   a.regimeADX=adx[1];
   return true;
}

int ReadTrendVote(int fastHandle,int slowHandle)
{
   double f[],s[];
   ArrayResize(f,3); ArrayResize(s,3);
   ArraySetAsSeries(f,true); ArraySetAsSeries(s,true);

   if(CopyBuffer(fastHandle,0,0,3,f)<3) return 0;
   if(CopyBuffer(slowHandle,0,0,3,s)<3) return 0;

   if(f[1]>s[1] && f[1]>f[2]) return 1;
   if(f[1]<s[1] && f[1]<f[2]) return -1;
   return 0;
}

bool ReadMarketQuality(AssetState &a)
{
   int need=InpVolatilityLookback+2;
   double atr[];
   ArraySetAsSeries(atr,true);

   if(CopyBuffer(a.hATR,0,0,need,atr)<need)
      return false;

   double currentATR=atr[1];
   if(currentATR<=0.0) return false;

   double sum=0.0;
   int count=0;
   for(int i=2;i<need;i++)
   {
      if(atr[i]>0.0)
      {
         sum+=atr[i];
         count++;
      }
   }

   if(count<=0) return false;
   double meanATR=sum/(double)count;
   if(meanATR<=0.0) return false;

   a.atrRatio=currentATR/meanATR;

   int barsNeed=InpShockCooldownBars+2;
   if(barsNeed<3) barsNeed=3;

   MqlRates r[];
   ArraySetAsSeries(r,true);
   if(CopyRates(a.symbol,a.entryTF,0,barsNeed,r)<barsNeed)
      return false;

   a.shockRangeATR=0.0;
   for(int i=1;i<=InpShockCooldownBars && i<ArraySize(r);i++)
   {
      double ratio=(r[i].high-r[i].low)/currentATR;
      if(ratio>a.shockRangeATR)
         a.shockRangeATR=ratio;
   }

   if(a.atrRatio<InpMinATRRatio || a.atrRatio>InpMaxATRRatio)
      return false;
   if(InpUseShockGuard && a.shockRangeATR>InpMaxClosedBarRangeATR)
      return false;

   return true;
}

double ComputeEntryQualityScore(AssetState &a,bool bullish)
{
   double score=0.0;

   if(a.zone.gapATR>=InpMinFVG_ATR) score+=10.0;
   if(a.zone.gapATR>=0.25) score+=5.0;
   if(a.zone.gapATR>=0.40) score+=5.0;

   if(a.zone.bodyATR>=InpMinBody_ATR) score+=10.0;
   if(a.zone.bodyATR>=0.80) score+=5.0;
   if(a.zone.bodyATR>=1.20) score+=5.0;

   if(a.zone.bodyRatio>=InpMinBodyRatio) score+=10.0;
   if(a.zone.bodyRatio>=0.70) score+=5.0;
   if(a.zone.bodyRatio>=0.80) score+=5.0;

   int aligned=bullish?a.mtfScore:-a.mtfScore;
   if(aligned<0) aligned=0;
   score+=5.0*(double)aligned;

   bool regimeAligned=bullish?(a.regimeFast>a.regimeSlow):(a.regimeFast<a.regimeSlow);
   bool slopeAligned=bullish?(a.regimeSlope>0.0):(a.regimeSlope<0.0);

   if(regimeAligned) score+=5.0;
   if(slopeAligned) score+=5.0;

   if(a.regimeADX>=InpMinADX) score+=5.0;
   if(a.regimeADX>=25.0) score+=5.0;

   if(a.atrRatio>=0.60 && a.atrRatio<=1.50) score+=5.0;
   if(a.spreadRatio<=1.50) score+=5.0;

   if(score>100.0) score=100.0;
   if(score<0.0) score=0.0;
   return score;
}

bool DirectionalQualityAllows(AssetState &a,bool bullish)
{
   int aligned=bullish?a.mtfScore:-a.mtfScore;
   if(aligned<MinAlignedVotes(a,bullish))
      return false;

   if(a.qualityScore<MinQuality(a,bullish))
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Re-entry                                                          |
//+------------------------------------------------------------------+
bool ReentryAllows(AssetState &a,bool bullish)
{
   if(a.zone.quarantined || a.zone.attempts>=MaxAttempts(a))
      return false;

   if(!InpUseControlledReentry)
      return true;

   if(a.zone.attempts<=0)
      return true;

   if(a.zone.lastExitTime<=0)
      return false;

   if(!InpAllowReentryAfterProfit && a.zone.lastRealizedR>0.0)
      return false;

   if(BarsSince(a,a.zone.lastExitTime)<InpReentryCooldownBars)
      return false;

   if(InpRequireClosedBarRejectionOnReentry &&
      !ClosedBarRejectionForReentry(a,bullish,InpReentryCloseThreshold))
      return false;

   if(a.zone.riskSpentPct>=InpMaxZoneRiskBudgetPct-1e-8)
      return false;

   return true;
}

int BarsSince(AssetState &a,datetime t)
{
   if(t<=0) return 1000000;
   int shift=iBarShift(a.symbol,a.entryTF,t,false);
   return shift<0?0:shift;
}

bool ClosedBarRejectionForReentry(AssetState &a,bool bullish,double threshold)
{
   MqlRates r[];
   ArraySetAsSeries(r,true);

   if(CopyRates(a.symbol,a.entryTF,0,3,r)<3)
      return false;

   if(a.zone.lastExitTime>0 && r[1].time<=a.zone.lastExitTime)
      return false;

   double range=r[1].high-r[1].low;
   if(range<=0.0) return false;

   bool touched=(r[1].low<=a.zone.high && r[1].high>=a.zone.low);
   if(!touched) return false;

   double closePos=(r[1].close-r[1].low)/range;

   if(bullish)
      return r[1].close>r[1].open && closePos>=threshold;

   return r[1].close<r[1].open && closePos<=(1.0-threshold);
}

//+------------------------------------------------------------------+
//| Entry                                                             |
//+------------------------------------------------------------------+
void TryFVGEntry(AssetState &a)
{
   MqlTick tick;
   if(!SymbolInfoTick(a.symbol,tick)) return;
   if(tick.bid<=0.0 || tick.ask<=0.0) return;

   double midpoint=(a.zone.low+a.zone.high)/2.0;

   if(a.zone.bullish)
   {
      if(tick.ask<a.zone.low || tick.ask>a.zone.high) return;
      if(InpRequireMidpoint && tick.ask>midpoint) return;
      if(InpRequireRejection && !BullishRejection(a)) return;
      OpenTrade(a,true);
   }
   else
   {
      if(tick.bid<a.zone.low || tick.bid>a.zone.high) return;
      if(InpRequireMidpoint && tick.bid<midpoint) return;
      if(InpRequireRejection && !BearishRejection(a)) return;
      OpenTrade(a,false);
   }
}

bool BullishRejection(AssetState &a)
{
   MqlRates r[];
   ArraySetAsSeries(r,true);
   if(CopyRates(a.symbol,a.entryTF,0,2,r)<2) return false;

   double bid=SymbolInfoDouble(a.symbol,SYMBOL_BID);
   double range=r[0].high-r[0].low;
   if(range<=0.0) return false;

   return (bid-r[0].low)/range>=0.55;
}

bool BearishRejection(AssetState &a)
{
   MqlRates r[];
   ArraySetAsSeries(r,true);
   if(CopyRates(a.symbol,a.entryTF,0,2,r)<2) return false;

   double ask=SymbolInfoDouble(a.symbol,SYMBOL_ASK);
   double range=r[0].high-r[0].low;
   if(range<=0.0) return false;

   return (ask-r[0].low)/range<=0.45;
}

bool OpenTrade(AssetState &a,bool bullish)
{
   double atr=GetATR(a);
   if(atr<=0.0) return false;

   MqlTick tick;
   if(!SymbolInfoTick(a.symbol,tick)) return false;

   double entry=bullish?tick.ask:tick.bid;
   if(entry<=0.0) return false;

   double sl=bullish?a.zone.low-atr*InpSL_ATR_Buffer:a.zone.high+atr*InpSL_ATR_Buffer;
   double riskDist=MathAbs(entry-sl);

   if(riskDist<=0.0 || riskDist>atr*InpMaxSL_ATR)
      return false;

   double rrTarget=RewardRisk(a);
   double tp=bullish?entry+riskDist*rrTarget:entry-riskDist*rrTarget;

   sl=NormalizePrice(a,sl);
   tp=NormalizePrice(a,tp);

   if(!StopsAreValid(a,entry,sl,tp,bullish))
      return false;

   int nextAttempt=a.zone.attempts+1;
   double attemptScale=(nextAttempt<=1)?1.0:InpSecondAttemptRiskScale;
   double combinedScale=attemptScale*PortfolioRiskScale()*DirectionRiskScale(a,bullish);

   if(combinedScale<=0.0)
      return false;

   double remaining=InpMaxZoneRiskBudgetPct-a.zone.riskSpentPct;
   if(remaining<=0.0)
      return false;

   double volume=0.0;
   double riskMoney=0.0;
   double riskPct=0.0;

   if(!CalculateVolume(a,entry,sl,bullish,combinedScale,remaining,volume,riskMoney,riskPct))
      return false;

   if(!MarginPreflight(a,bullish,volume,entry))
      return false;

   trade.SetExpertMagicNumber(a.magic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(a.symbol);

   bool ok=bullish
      ? trade.Buy(volume,a.symbol,0.0,sl,tp,"AUREON V4")
      : trade.Sell(volume,a.symbol,0.0,sl,tp,"AUREON V4");

   if(!ok)
   {
      Print("AUREON V4 trade failed ",a.symbol,": ",trade.ResultRetcodeDescription());
      return false;
   }

   uint rc=trade.ResultRetcode();
   if(rc!=TRADE_RETCODE_DONE && rc!=TRADE_RETCODE_DONE_PARTIAL && rc!=TRADE_RETCODE_PLACED)
   {
      Print("AUREON V4 trade rejected ",a.symbol,": ",trade.ResultRetcodeDescription());
      return false;
   }

   a.zone.attempts++;
   a.zone.lastRiskMoney=riskMoney;
   a.zone.riskSpentPct+=riskPct;
   PersistZone(a);

   WriteTelemetry(a,"ENTRY",0.0,0.0,riskPct,volume);

   Print("AUREON V4 entry | ",a.symbol,
         " ",bullish?"BUY":"SELL",
         " quality=",DoubleToString(a.qualityScore,1),
         " mtf=",a.mtfScore,
         " risk%=",DoubleToString(riskPct,3),
         " volume=",DoubleToString(volume,4),
         " attempt=",a.zone.attempts);

   return true;
}

bool EstimateStopLossMoney(AssetState &a,double entry,double sl,bool bullish,double volume,
                           double &lossMoney,bool &usedFallback)
{
   lossMoney=0.0;
   usedFallback=false;

   ENUM_ORDER_TYPE type=bullish?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double brokerCalc=0.0;
   ResetLastError();
   bool brokerOK=OrderCalcProfit(type,a.symbol,volume,entry,sl,brokerCalc);

   if(brokerOK && MathAbs(brokerCalc)>1e-8)
   {
      lossMoney=MathAbs(brokerCalc);
      return true;
   }

   // PrimeXBT demo catalogue validation (2026-09-27) showed BTCUSDT as
   // fully tradable while SYMBOL_TRADE_TICK_VALUE and OrderCalcProfit()
   // returned zero because the instrument profit currency is UST. Fail
   // closed for every other instrument; only the validated BTCUSDT-style
   // contract can use this conservative fallback.
   if(!InpUseBitcoinManualRiskFallback || a.kind!=AUREON_KIND_BITCOIN)
      return false;

   string upper=a.symbol;
   StringToUpper(upper);
   if(StringFind(upper,"BTCUSDT")<0)
      return false;

   string accountCurrency=AccountInfoString(ACCOUNT_CURRENCY);
   string profitCurrency=SymbolInfoString(a.symbol,SYMBOL_CURRENCY_PROFIT);
   if(accountCurrency!="USD" || (profitCurrency!="UST" && profitCurrency!="USDT"))
      return false;

   double contract=SymbolInfoDouble(a.symbol,SYMBOL_TRADE_CONTRACT_SIZE);
   if(contract<=0.0 || InpBitcoinUSTUSDConversion<=0.0 ||
      InpBitcoinFallbackRiskSafetyMultiplier<1.0)
      return false;

   // MQL5 CFD/CFD-index profit formula:
   // (close-open) * contract_size * lots. Convert UST/USDT to account USD
   // using the explicit profile factor, then overstate risk by the safety
   // multiplier so sizing remains conservative.
   double nativeLoss=MathAbs(entry-sl)*contract*volume;
   lossMoney=nativeLoss*InpBitcoinUSTUSDConversion*InpBitcoinFallbackRiskSafetyMultiplier;
   usedFallback=(lossMoney>0.0);

   if(usedFallback && InpVerboseLog)
      Print("AUREON V4.10 BTC risk fallback | symbol=",a.symbol,
            " profitCurrency=",profitCurrency,
            " loss=",DoubleToString(lossMoney,2),
            " volume=",DoubleToString(volume,4));

   return lossMoney>0.0;
}

bool CalculateVolume(AssetState &a,double entry,double sl,bool bullish,
                     double scale,double zoneRemainingPct,
                     double &volume,double &riskMoney,double &riskPct)
{
   volume=0.0;
   riskMoney=0.0;
   riskPct=0.0;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity<=0.0 || scale<=0.0) return false;

   double targetPct=BaseRiskPct(a)*scale;
   if(targetPct>zoneRemainingPct)
      targetPct=zoneRemainingPct;

   if(targetPct<=0.0) return false;

   double oneLotLoss=0.0;
   bool usedFallback=false;
   if(!EstimateStopLossMoney(a,entry,sl,bullish,1.0,oneLotLoss,usedFallback))
      return false;

   if(oneLotLoss<=0.0) return false;

   double targetMoney=equity*targetPct/100.0;
   double raw=targetMoney/oneLotLoss;

   double minLot=SymbolInfoDouble(a.symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(a.symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(a.symbol,SYMBOL_VOLUME_STEP);

   if(minLot<=0.0 || maxLot<=0.0 || step<=0.0)
      return false;

   volume=MathFloor(raw/step)*step;
   if(volume>maxLot) volume=maxLot;
   volume=NormalizeVolume(a,volume);

   if(volume<minLot)
      return false;

   bool finalFallback=false;
   if(!EstimateStopLossMoney(a,entry,sl,bullish,volume,riskMoney,finalFallback))
      return false;

   riskPct=riskMoney/equity*100.0;

   if(riskPct>targetPct+1e-6)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Position management                                               |
//+------------------------------------------------------------------+
void ManageOpenPosition(AssetState &a)
{
   ulong ticket=GetOurPositionTicket(a);
   if(ticket==0 || !PositionSelectByTicket(ticket))
      return;

   long type=PositionGetInteger(POSITION_TYPE);
   double open=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl=PositionGetDouble(POSITION_SL);
   double tp=PositionGetDouble(POSITION_TP);

   double price=(type==POSITION_TYPE_BUY)
      ?SymbolInfoDouble(a.symbol,SYMBOL_BID)
      :SymbolInfoDouble(a.symbol,SYMBOL_ASK);

   double rrTarget=RewardRisk(a);

   if(open<=0.0 || price<=0.0 || tp<=0.0 || rrTarget<=0.0)
      return;

   double initialRisk=MathAbs(tp-open)/rrTarget;
   if(initialRisk<=0.0) return;

   double move=(type==POSITION_TYPE_BUY)?price-open:open-price;
   double rr=move/initialRisk;
   if(rr<=0.0) return;

   if(InpUseProfitLock)
   {
      double lockRR=-1.0;
      if(rr>=InpLock2TriggerRR) lockRR=InpLock2RR;
      else if(rr>=InpLock1TriggerRR) lockRR=InpLock1RR;

      if(lockRR>=0.0)
      {
         double newSL=(type==POSITION_TYPE_BUY)
            ?open+initialRisk*lockRR
            :open-initialRisk*lockRR;

         newSL=NormalizePrice(a,newSL);

         if(IsBetterSL(type,sl,newSL) &&
            StopsAreValid(a,price,newSL,tp,type==POSITION_TYPE_BUY))
         {
            if(SafeModifyPosition(a,ticket,newSL,tp,"LOCK"))
               sl=newSL;
         }
      }
   }

   if(!InpUseSmartTrail || rr<InpTrailStartRR)
      return;

   double atr=GetATR(a);
   if(atr<=0.0) return;

   double trailATR=(rr>=InpTrailTightenRR)?InpTrailTightATR:InpTrailATR;

   double newSL=(type==POSITION_TYPE_BUY)
      ?price-atr*trailATR
      :price+atr*trailATR;

   double floorSL=(type==POSITION_TYPE_BUY)
      ?open+initialRisk*InpTrailFloorRR
      :open-initialRisk*InpTrailFloorRR;

   if(type==POSITION_TYPE_BUY)
      newSL=MathMax(newSL,floorSL);
   else
      newSL=MathMin(newSL,floorSL);

   newSL=NormalizePrice(a,newSL);

   if(IsBetterSL(type,sl,newSL) &&
      StopsAreValid(a,price,newSL,tp,type==POSITION_TYPE_BUY))
      SafeModifyPosition(a,ticket,newSL,tp,"TRAIL");
}

bool SafeModifyPosition(AssetState &a,ulong ticket,double newSL,double tp,string reason)
{
   trade.SetExpertMagicNumber(a.magic);
   trade.SetDeviationInPoints(InpDeviationPoints);

   ResetLastError();
   bool ok=trade.PositionModify(ticket,newSL,tp);
   uint rc=trade.ResultRetcode();

   if(!ok || (rc!=TRADE_RETCODE_DONE && rc!=TRADE_RETCODE_NO_CHANGES && rc!=TRADE_RETCODE_PLACED))
   {
      Print("AUREON V4 modify failed [",reason,"] ",a.symbol,
            " rc=",rc," ",trade.ResultRetcodeDescription()," err=",GetLastError());
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Permission and broker guards                                      |
//+------------------------------------------------------------------+
bool TradingAllowed(AssetState &a)
{
   if(!InpExecutionArmed)
      return false;

   if(InpDemoOnly &&
      !MQLInfoInteger(MQL_TESTER) &&
      (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO)
      return false;

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;

   if(SymbolInfoInteger(a.symbol,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL)
      return false;

   MqlTick tick;
   if(!SymbolInfoTick(a.symbol,tick)) return false;
   if(tick.bid<=0.0 || tick.ask<=0.0 || tick.time<=0) return false;

   if(InpMaxTickAgeSeconds>0 && (TimeCurrent()-tick.time)>InpMaxTickAgeSeconds)
      return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   bool weekend=(dt.day_of_week==0 || dt.day_of_week==6);

   if(weekend && a.kind==AUREON_KIND_GOLD)
      return false;

   if(weekend && a.kind==AUREON_KIND_BITCOIN && !InpBitcoinAllowWeekend)
      return false;

   double point=SymbolInfoDouble(a.symbol,SYMBOL_POINT);
   if(point<=0.0) return false;

   double spreadPrice=tick.ask-tick.bid;
   double spreadPoints=spreadPrice/point;

   int fixedMax=FixedMaxSpreadPoints(a);
   if(fixedMax>0 && spreadPoints>fixedMax)
      return false;

   double atr=GetATR(a);
   if(atr<=0.0) return false;

   if(InpMaxSpreadATRRatio>0.0 && spreadPrice/atr>InpMaxSpreadATRRatio)
      return false;

   if(InpUseRelativeSpreadGuard &&
      a.spreadSamples>=InpSpreadEMAWarmupTicks &&
      a.spreadEMA>0.0 &&
      spreadPoints>a.spreadEMA*InpRelativeSpreadMultiplier)
      return false;

   if(PortfolioDailyLossPct()>=InpPortfolioDailyLossPct)
      return false;

   if(PortfolioDrawdownPct()>=InpPortfolioHardStopDDPct)
      return false;

   return true;
}

void UpdateSpreadState(AssetState &a)
{
   MqlTick tick;
   if(!SymbolInfoTick(a.symbol,tick)) return;
   if(tick.time_msc<=0 || tick.time_msc==a.lastSpreadTickMsc) return;

   double point=SymbolInfoDouble(a.symbol,SYMBOL_POINT);
   if(point<=0.0 || tick.bid<=0.0 || tick.ask<=0.0) return;

   double spread=(tick.ask-tick.bid)/point;
   if(spread<0.0) return;

   double alpha=2.0/((double)InpSpreadEMAWarmupTicks+1.0);

   if(a.spreadSamples<=0 || a.spreadEMA<=0.0)
      a.spreadEMA=spread;
   else
      a.spreadEMA=a.spreadEMA+alpha*(spread-a.spreadEMA);

   a.spreadSamples++;
   a.spreadRatio=(a.spreadEMA>0.0)?spread/a.spreadEMA:1.0;
   a.lastSpreadTickMsc=tick.time_msc;
}

bool MarginPreflight(AssetState &a,bool bullish,double volume,double entry)
{
   ENUM_ORDER_TYPE type=bullish?ORDER_TYPE_BUY:ORDER_TYPE_SELL;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double currentMargin=AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(equity<=0.0 || freeMargin<=0.0)
      return false;

   // First ask MT5/broker to validate the exact market request. OrderCheck()
   // does not send the order. For PrimeXBT BTCUSDT this is mandatory because
   // the catalogue's client-side OrderCalcMargin metadata currently resolves
   // to zero.
   MqlTradeRequest request={};
   MqlTradeCheckResult check={};
   request.action=TRADE_ACTION_DEAL;
   request.symbol=a.symbol;
   request.volume=volume;
   request.type=type;
   request.price=entry;
   request.deviation=InpDeviationPoints;
   request.magic=a.magic;

   ResetLastError();
   bool checkOK=OrderCheck(request,check);

   if(checkOK && check.retcode==0)
   {
      double incremental=MathMax(0.0,check.margin-currentMargin);

      if(check.margin_free<=0.0)
         return false;

      if(InpMaxSingleTradeMarginPct>0.0 &&
         incremental/equity*100.0>InpMaxSingleTradeMarginPct)
         return false;

      if(InpMinProjectedMarginLevelPct>0.0 &&
         check.margin>0.0 &&
         check.margin_level<InpMinProjectedMarginLevelPct)
         return false;

      if(a.kind==AUREON_KIND_BITCOIN && incremental<=0.0)
      {
         if(InpVerboseLog)
            Print("AUREON V4.10 BTC OrderCheck returned zero incremental margin; entry rejected.");
         return false;
      }

      return true;
   }

   if(a.kind==AUREON_KIND_BITCOIN && InpRequireBitcoinServerOrderCheck)
   {
      if(InpVerboseLog)
         Print("AUREON V4.10 BTC OrderCheck rejected/preflight unavailable | retcode=",
               check.retcode," comment=",check.comment," err=",GetLastError());
      return false;
   }

   // Gold and non-BTC fallback: retain client-side margin calculation.
   double required=0.0;
   if(!OrderCalcMargin(type,a.symbol,volume,entry,required) || required<=0.0)
      return false;

   if(required>freeMargin)
      return false;

   if(InpMaxSingleTradeMarginPct>0.0 &&
      required/equity*100.0>InpMaxSingleTradeMarginPct)
      return false;

   double projected=currentMargin+required;
   if(projected>0.0 && InpMinProjectedMarginLevelPct>0.0)
   {
      double projectedLevel=equity/projected*100.0;
      if(projectedLevel<InpMinProjectedMarginLevelPct)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Shared portfolio governor                                         |
//+------------------------------------------------------------------+
string AccountPrefix()
{
   return StringFormat("AP4_%I64d_",AccountInfoInteger(ACCOUNT_LOGIN));
}

int TodayKey()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   return dt.year*1000+dt.day_of_year;
}

void EnsurePortfolioState()
{
   string p=AccountPrefix();
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   int day=TodayKey();

   if(!GlobalVariableCheck(p+"DAY_KEY") ||
      (int)GlobalVariableGet(p+"DAY_KEY")!=day)
   {
      GlobalVariableSet(p+"DAY_KEY",(double)day);
      GlobalVariableSet(p+"DAY_EQ",equity);
   }
   else if(!GlobalVariableCheck(p+"DAY_EQ"))
      GlobalVariableSet(p+"DAY_EQ",equity);

   if(!GlobalVariableCheck(p+"EQ_PEAK"))
      GlobalVariableSet(p+"EQ_PEAK",equity);
}

void UpdatePortfolioPeak()
{
   string key=AccountPrefix()+"EQ_PEAK";
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity<=0.0) return;

   double peak=GlobalVariableCheck(key)?GlobalVariableGet(key):equity;
   if(equity>peak)
      GlobalVariableSet(key,equity);
}

double PortfolioDailyLossPct()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   string key=AccountPrefix()+"DAY_EQ";

   if(!GlobalVariableCheck(key)) return 0.0;

   double start=GlobalVariableGet(key);
   if(start<=0.0 || equity>=start) return 0.0;

   return (start-equity)/start*100.0;
}

double PortfolioDrawdownPct()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   string key=AccountPrefix()+"EQ_PEAK";

   if(!GlobalVariableCheck(key)) return 0.0;

   double peak=GlobalVariableGet(key);
   if(peak<=0.0 || equity>=peak) return 0.0;

   return (peak-equity)/peak*100.0;
}

double PortfolioRiskScale()
{
   double dd=PortfolioDrawdownPct();

   if(dd>=InpPortfolioHardStopDDPct) return 0.0;
   if(dd>=InpPortfolioDDStage2Pct) return InpPortfolioDDStage2Scale;
   if(dd>=InpPortfolioDDStage1Pct) return InpPortfolioDDStage1Scale;

   return 1.0;
}

//+------------------------------------------------------------------+
//| Asset profile helpers                                             |
//+------------------------------------------------------------------+
string AssetName(const AssetState &a)
{
   return a.kind==AUREON_KIND_GOLD?"GOLD":"BITCOIN";
}

double BaseRiskPct(const AssetState &a)
{
   return a.kind==AUREON_KIND_GOLD?InpGoldRiskPct:InpBitcoinRiskPct;
}

double DirectionRiskScale(const AssetState &a,bool bullish)
{
   if(a.kind==AUREON_KIND_GOLD)
      return bullish?InpGoldLongRiskScale:InpGoldShortRiskScale;

   return bullish?InpBitcoinLongRiskScale:InpBitcoinShortRiskScale;
}

double MinQuality(const AssetState &a,bool bullish)
{
   if(a.kind==AUREON_KIND_GOLD)
      return bullish?InpGoldMinLongQuality:InpGoldMinShortQuality;

   return bullish?InpBitcoinMinLongQuality:InpBitcoinMinShortQuality;
}

int MinAlignedVotes(const AssetState &a,bool bullish)
{
   if(a.kind==AUREON_KIND_GOLD)
      return bullish?InpGoldLongMinAlignedVotes:InpGoldShortMinAlignedVotes;

   return bullish?InpBitcoinLongMinAlignedVotes:InpBitcoinShortMinAlignedVotes;
}

int MaxAttempts(const AssetState &a)
{
   return a.kind==AUREON_KIND_GOLD?InpGoldMaxAttemptsPerFVG:InpBitcoinMaxAttemptsPerFVG;
}

int MaxTradesDay(const AssetState &a)
{
   return a.kind==AUREON_KIND_GOLD?InpGoldMaxTradesDay:InpBitcoinMaxTradesDay;
}

double RewardRisk(const AssetState &a)
{
   return a.kind==AUREON_KIND_GOLD?InpGoldRewardRisk:InpBitcoinRewardRisk;
}

int FixedMaxSpreadPoints(const AssetState &a)
{
   return a.kind==AUREON_KIND_GOLD?InpGoldMaxSpreadPoints:InpBitcoinMaxSpreadPoints;
}

//+------------------------------------------------------------------+
//| Persistence                                                       |
//+------------------------------------------------------------------+
string ZonePrefix(const AssetState &a)
{
   string sym=a.symbol;
   StringReplace(sym,".","_");
   StringReplace(sym,"#","_");
   StringReplace(sym,"-","_");

   return AccountPrefix()+sym+"_"+IntegerToString(a.kind)+"_";
}

void PersistZone(AssetState &a)
{
   if(!InpPersistState) return;

   string p=ZonePrefix(a);

   GlobalVariableSet(p+"VALID",a.zone.valid?1.0:0.0);
   GlobalVariableSet(p+"BULL",a.zone.bullish?1.0:0.0);
   GlobalVariableSet(p+"LOW",a.zone.low);
   GlobalVariableSet(p+"HIGH",a.zone.high);
   GlobalVariableSet(p+"FORMED",(double)a.zone.formed);
   GlobalVariableSet(p+"ATT",(double)a.zone.attempts);
   GlobalVariableSet(p+"LAST_EXIT",(double)a.zone.lastExitTime);
   GlobalVariableSet(p+"LAST_R",a.zone.lastRealizedR);
   GlobalVariableSet(p+"LAST_RISK",a.zone.lastRiskMoney);
   GlobalVariableSet(p+"GAP",a.zone.gapATR);
   GlobalVariableSet(p+"BODY",a.zone.bodyATR);
   GlobalVariableSet(p+"RATIO",a.zone.bodyRatio);
   GlobalVariableSet(p+"RISK_USED",a.zone.riskSpentPct);
   GlobalVariableSet(p+"QUAR",a.zone.quarantined?1.0:0.0);
}

void LoadZoneState(AssetState &a)
{
   string p=ZonePrefix(a);

   if(!GlobalVariableCheck(p+"VALID"))
      return;

   a.zone.valid=GlobalVariableGet(p+"VALID")>0.5;
   a.zone.bullish=GlobalVariableCheck(p+"BULL") && GlobalVariableGet(p+"BULL")>0.5;
   a.zone.low=GlobalVariableCheck(p+"LOW")?GlobalVariableGet(p+"LOW"):0.0;
   a.zone.high=GlobalVariableCheck(p+"HIGH")?GlobalVariableGet(p+"HIGH"):0.0;
   a.zone.formed=GlobalVariableCheck(p+"FORMED")?(datetime)GlobalVariableGet(p+"FORMED"):0;
   a.zone.attempts=GlobalVariableCheck(p+"ATT")?(int)GlobalVariableGet(p+"ATT"):0;
   a.zone.lastExitTime=GlobalVariableCheck(p+"LAST_EXIT")?(datetime)GlobalVariableGet(p+"LAST_EXIT"):0;
   a.zone.lastRealizedR=GlobalVariableCheck(p+"LAST_R")?GlobalVariableGet(p+"LAST_R"):0.0;
   a.zone.lastRiskMoney=GlobalVariableCheck(p+"LAST_RISK")?GlobalVariableGet(p+"LAST_RISK"):0.0;
   a.zone.gapATR=GlobalVariableCheck(p+"GAP")?GlobalVariableGet(p+"GAP"):0.0;
   a.zone.bodyATR=GlobalVariableCheck(p+"BODY")?GlobalVariableGet(p+"BODY"):0.0;
   a.zone.bodyRatio=GlobalVariableCheck(p+"RATIO")?GlobalVariableGet(p+"RATIO"):0.0;
   a.zone.riskSpentPct=GlobalVariableCheck(p+"RISK_USED")?GlobalVariableGet(p+"RISK_USED"):0.0;
   a.zone.quarantined=GlobalVariableCheck(p+"QUAR") && GlobalVariableGet(p+"QUAR")>0.5;

   if(a.zone.valid && FVGExpired(a,a.zone))
      a.zone.valid=false;
}

//+------------------------------------------------------------------+
//| Telemetry                                                         |
//+------------------------------------------------------------------+
void EnsureTelemetryHeader()
{
   int h=FileOpen(InpTelemetryFile,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(h==INVALID_HANDLE) return;

   if(FileSize(h)==0)
   {
      FileWrite(h,
         "event","time","symbol","asset","magic","direction","zone_formed",
         "attempts","gap_atr","body_atr","body_ratio","mtf_score","quality",
         "atr_ratio","spread_ratio","portfolio_daily_loss_pct","portfolio_dd_pct",
         "risk_pct","volume","realized_r","net");
   }

   FileClose(h);
}

void WriteTelemetry(AssetState &a,string eventName,double realizedR,double net,
                    double riskPct,double volume)
{
   if(!InpEnableTelemetry) return;

   int h=FileOpen(InpTelemetryFile,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(h==INVALID_HANDLE) return;

   FileSeek(h,0,SEEK_END);

   FileWrite(h,
      eventName,
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      a.symbol,
      AssetName(a),
      (long)a.magic,
      a.zone.bullish?"BUY":"SELL",
      TimeToString(a.zone.formed,TIME_DATE|TIME_SECONDS),
      a.zone.attempts,
      DoubleToString(a.zone.gapATR,4),
      DoubleToString(a.zone.bodyATR,4),
      DoubleToString(a.zone.bodyRatio,4),
      a.mtfScore,
      DoubleToString(a.qualityScore,2),
      DoubleToString(a.atrRatio,4),
      DoubleToString(a.spreadRatio,4),
      DoubleToString(PortfolioDailyLossPct(),3),
      DoubleToString(PortfolioDrawdownPct(),3),
      DoubleToString(riskPct,4),
      DoubleToString(volume,4),
      DoubleToString(realizedR,4),
      DoubleToString(net,2));

   FileClose(h);
}

//+------------------------------------------------------------------+
//| Position/history helpers                                          |
//+------------------------------------------------------------------+
bool HasOurPosition(AssetState &a)
{
   return GetOurPositionTicket(a)!=0;
}

ulong GetOurPositionTicket(AssetState &a)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL)==a.symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)==a.magic)
         return ticket;
   }

   return 0;
}

int CountOpenPositionsAll()
{
   return PositionsTotal();
}

int CountTodayEntries(AssetState &a)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   dt.hour=0;
   dt.min=0;
   dt.sec=0;

   datetime from=StructToTime(dt);
   datetime to=TimeCurrent();

   if(!HistorySelect(from,to))
      return 0;

   int count=0;

   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=a.symbol) continue;
      if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=a.magic) continue;

      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_IN)
         count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| Utility                                                           |
//+------------------------------------------------------------------+
double GetATR(AssetState &a)
{
   double v[];
   ArrayResize(v,2);
   ArraySetAsSeries(v,true);

   if(CopyBuffer(a.hATR,0,0,2,v)<2)
      return 0.0;

   return v[1];
}

bool IsNewBar(AssetState &a)
{
   datetime t=iTime(a.symbol,a.entryTF,0);

   if(t==0) return false;

   if(t!=a.lastBar)
   {
      a.lastBar=t;
      return true;
   }

   return false;
}

bool StopsAreValid(AssetState &a,double price,double sl,double tp,bool bullish)
{
   double point=SymbolInfoDouble(a.symbol,SYMBOL_POINT);
   if(point<=0.0) return false;

   long stops=SymbolInfoInteger(a.symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze=SymbolInfoInteger(a.symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist=MathMax(stops,freeze)*point;

   if(bullish)
      return sl<price && tp>price && price-sl>=minDist && tp-price>=minDist;

   return sl>price && tp<price && sl-price>=minDist && price-tp>=minDist;
}

bool IsBetterSL(long type,double oldSL,double newSL)
{
   if(type==POSITION_TYPE_BUY)
      return oldSL==0.0 || newSL>oldSL;

   return oldSL==0.0 || newSL<oldSL;
}

double NormalizePrice(AssetState &a,double price)
{
   int digits=(int)SymbolInfoInteger(a.symbol,SYMBOL_DIGITS);
   return NormalizeDouble(price,digits);
}

double NormalizeVolume(AssetState &a,double volume)
{
   double step=SymbolInfoDouble(a.symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0) return 0.0;

   int digits=0;
   double x=step;

   while(x<1.0 && digits<8)
   {
      x*=10.0;
      digits++;
   }

   return NormalizeDouble(volume,digits);
}

void ReleaseHandle(int handle)
{
   if(handle!=INVALID_HANDLE)
      IndicatorRelease(handle);
}

bool ValidateInputs()
{
   if(!InpEnableGold && !InpEnableBitcoin) return false;
   if(InpTimerSeconds<1 || InpMagicBase==0) return false;
   if(InpPortfolioMaxOpenPositions<1) return false;

   if(InpPortfolioDailyLossPct<=0.0 || InpPortfolioHardStopDDPct<=0.0)
      return false;

   if(InpPortfolioDDStage1Pct<=0.0 ||
      InpPortfolioDDStage2Pct<=InpPortfolioDDStage1Pct ||
      InpPortfolioHardStopDDPct<=InpPortfolioDDStage2Pct)
      return false;

   if(InpPortfolioDDStage1Scale<=0.0 || InpPortfolioDDStage1Scale>1.0 ||
      InpPortfolioDDStage2Scale<=0.0 || InpPortfolioDDStage2Scale>InpPortfolioDDStage1Scale)
      return false;

   if(InpATRPeriod<1 || InpFastEMA<1 || InpSlowEMA<=InpFastEMA || InpADXPeriod<1)
      return false;

   if(InpMinFVG_ATR<=0.0 || InpMinBody_ATR<=0.0 ||
      InpMinBodyRatio<=0.0 || InpMinBodyRatio>1.0)
      return false;

   if(InpVolatilityLookback<5 || InpMinATRRatio<0.0 ||
      InpMaxATRRatio<=InpMinATRRatio)
      return false;

   if(InpSpreadEMAWarmupTicks<10 || InpRelativeSpreadMultiplier<=1.0)
      return false;

   if(InpReentryCloseThreshold<=0.5 || InpReentryCloseThreshold>=1.0 ||
      InpSecondAttemptRiskScale<=0.0 || InpSecondAttemptRiskScale>1.0 ||
      InpMaxZoneRiskBudgetPct<=0.0)
      return false;

   if(InpGoldRiskPct<=0.0 || InpBitcoinRiskPct<=0.0)
      return false;

   if(InpBitcoinUSTUSDConversion<=0.0 ||
      InpBitcoinFallbackRiskSafetyMultiplier<1.0)
      return false;

   return true;
}
//+------------------------------------------------------------------+
