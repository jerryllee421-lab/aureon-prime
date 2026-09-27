//+------------------------------------------------------------------+
//| AUREON_PRIME_MT5_V3_00_DUAL_ASSET.mq5                            |
//| Gold 24/5 + Bitcoin 24/7 demo-forward automation kernel           |
//| Derived from the proven V2.30 AsymmetricEdge research branch      |
//+------------------------------------------------------------------+
#property strict
#property version   "3.00"
#property description "AUREON PRIME MT5 V3.00: dual-asset XAU/BTC FVG-liquidity execution engine with shared portfolio risk governor, demo-only guard, MTF quality scoring, controlled re-entry, persistent state and adaptive trade management."

#include <Trade/Trade.mqh>
CTrade trade;

enum ENUM_AUREON_ASSET_MODE
{
   AUREON_AUTO = 0,
   AUREON_GOLD = 1,
   AUREON_BITCOIN = 2
};

//--------------------------- Safety -----------------------------------
input group "AUREON Safety"
input bool InpExecutionArmed = false;
input bool InpDemoOnly = true;
input ENUM_AUREON_ASSET_MODE InpAssetMode = AUREON_AUTO;
input ulong InpMagicBase = 26093000;
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

//--------------------------- Gold profile -----------------------------
input group "Gold profile"
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
input group "Bitcoin profile"
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

//--------------------------- FVG model --------------------------------
input group "FVG / Displacement model"
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

//--------------------------- MTF / quality ----------------------------
input group "MTF / Market quality"
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

//--------------------------- Re-entry ---------------------------------
input group "Controlled re-entry"
input bool InpUseControlledReentry = true;
input int InpReentryCooldownBars = 3;
input bool InpRequireClosedBarRejectionOnReentry = true;
input double InpReentryCloseThreshold = 0.60;
input bool InpAllowReentryAfterProfit = false;
input double InpQuarantineLossR = 1.50;
input double InpSecondAttemptRiskScale = 0.65;
input double InpMaxZoneRiskBudgetPct = 1.20;

//--------------------------- Position management ----------------------
input group "Position management"
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

//--------------------------- Telemetry --------------------------------
input group "Telemetry / State"
input bool InpPersistState = true;
input bool InpEnableTelemetry = true;
input string InpTelemetryFile = "AUREON_PRIME_MT5_V3.csv";
input bool InpVerboseLog = false;

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

int g_asset = 0;
ulong g_magic = 0;
ENUM_TIMEFRAMES g_entryTF = PERIOD_M1;
ENUM_TIMEFRAMES g_regimeTF = PERIOD_M15;

int hATR = INVALID_HANDLE;
int hRegimeFast = INVALID_HANDLE;
int hRegimeSlow = INVALID_HANDLE;
int hADX = INVALID_HANDLE;
int hTF1Fast = INVALID_HANDLE;
int hTF1Slow = INVALID_HANDLE;
int hTF2Fast = INVALID_HANDLE;
int hTF2Slow = INVALID_HANDLE;
int hTF3Fast = INVALID_HANDLE;
int hTF3Slow = INVALID_HANDLE;

datetime g_lastBar = 0;
FVGZone g_zone;
double g_spreadEMA = 0.0;
int g_spreadSamples = 0;
int g_mtfScore = 0;
double g_qualityScore = 0.0;
double g_atrRatio = 0.0;
double g_shockRangeATR = 0.0;
double g_spreadRatio = 1.0;
double g_regimeFast = 0.0;
double g_regimeSlow = 0.0;
double g_regimeSlope = 0.0;
double g_regimeADX = 0.0;

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   g_asset = ResolveAssetMode();
   if(g_asset == 0)
   {
      Print("AUREON PRIME: unsupported symbol for AUTO mode: ", _Symbol);
      return INIT_PARAMETERS_INCORRECT;
   }

   g_entryTF = EntryTF();
   g_regimeTF = RegimeTF();
   g_magic = InpMagicBase + (ulong)g_asset;

   trade.SetExpertMagicNumber(g_magic);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   hATR = iATR(_Symbol, g_entryTF, InpATRPeriod);
   hRegimeFast = iMA(_Symbol, g_regimeTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRegimeSlow = iMA(_Symbol, g_regimeTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hADX = iADX(_Symbol, g_regimeTF, InpADXPeriod);

   hTF1Fast = iMA(_Symbol, ContextTF1(), InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTF1Slow = iMA(_Symbol, ContextTF1(), InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTF2Fast = iMA(_Symbol, ContextTF2(), InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTF2Slow = iMA(_Symbol, ContextTF2(), InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTF3Fast = iMA(_Symbol, ContextTF3(), InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTF3Slow = iMA(_Symbol, ContextTF3(), InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);

   if(hATR == INVALID_HANDLE || hRegimeFast == INVALID_HANDLE || hRegimeSlow == INVALID_HANDLE ||
      hADX == INVALID_HANDLE || hTF1Fast == INVALID_HANDLE || hTF1Slow == INVALID_HANDLE ||
      hTF2Fast == INVALID_HANDLE || hTF2Slow == INVALID_HANDLE ||
      hTF3Fast == INVALID_HANDLE || hTF3Slow == INVALID_HANDLE)
      return INIT_FAILED;

   ResetZone();
   if(InpPersistState)
      LoadZoneState();

   EnsurePortfolioState();
   if(InpEnableTelemetry)
      EnsureTelemetryHeader();

   Print("AUREON PRIME MT5 V3.00 | symbol=", _Symbol,
         " asset=", AssetName(),
         " magic=", (long)g_magic,
         " entryTF=", EnumToString(g_entryTF),
         " armed=", InpExecutionArmed,
         " demoOnly=", InpDemoOnly);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(InpPersistState)
      SaveZoneState();

   ReleaseHandle(hATR);
   ReleaseHandle(hRegimeFast);
   ReleaseHandle(hRegimeSlow);
   ReleaseHandle(hADX);
   ReleaseHandle(hTF1Fast);
   ReleaseHandle(hTF1Slow);
   ReleaseHandle(hTF2Fast);
   ReleaseHandle(hTF2Slow);
   ReleaseHandle(hTF3Fast);
   ReleaseHandle(hTF3Slow);
}

//+------------------------------------------------------------------+
//| Tick                                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   EnsurePortfolioState();
   UpdatePortfolioPeak();
   UpdateSpreadState();
   ManageOpenPosition();

   if(IsNewBar())
      UpdateFVG();

   if(!TradingAllowed()) return;
   if(InpOnePositionPerSymbol && HasOurPosition()) return;
   if(CountOpenPositionsAll() >= InpPortfolioMaxOpenPositions) return;
   if(CountTodayEntries() >= MaxTradesDay()) return;

   if(!g_zone.valid || g_zone.quarantined) return;
   if(!ZoneStillValid())
   {
      g_zone.valid = false;
      PersistZone();
      return;
   }

   if(!RefreshContext(g_zone.bullish)) return;
   g_qualityScore = ComputeEntryQualityScore(g_zone.bullish);
   if(!DirectionalQualityAllows(g_zone.bullish)) return;
   if(!ReentryAllows(g_zone.bullish)) return;

   TryFVGEntry();
}

//+------------------------------------------------------------------+
//| Trade transaction                                                 |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != g_magic)
      return;

   ENUM_DEAL_ENTRY entryType=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY)
      return;

   double net = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
              + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION)
              + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
              + HistoryDealGetDouble(trans.deal, DEAL_FEE);

   double realizedR = (g_zone.lastRiskMoney > 0.0) ? net / g_zone.lastRiskMoney : 0.0;
   g_zone.lastExitTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   g_zone.lastRealizedR = realizedR;

   if(realizedR <= -InpQuarantineLossR)
      g_zone.quarantined = true;
   if(g_zone.attempts >= MaxAttemptsPerFVG())
      g_zone.quarantined = true;

   PersistZone();
   WriteTelemetry("EXIT", realizedR, net, 0.0, 0.0);

   if(InpVerboseLog)
      Print("AUREON exit | symbol=",_Symbol," R=",DoubleToString(realizedR,3),
            " net=",DoubleToString(net,2)," attempts=",g_zone.attempts);
}

//+------------------------------------------------------------------+
//| Configuration helpers                                             |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
   if(InpMagicBase == 0 || InpATRPeriod < 1 || InpFastEMA < 1 || InpSlowEMA <= InpFastEMA)
      return false;
   if(InpPortfolioDailyLossPct <= 0.0 || InpPortfolioHardStopDDPct <= 0.0)
      return false;
   if(InpPortfolioDDStage1Pct <= 0.0 || InpPortfolioDDStage2Pct <= InpPortfolioDDStage1Pct ||
      InpPortfolioHardStopDDPct <= InpPortfolioDDStage2Pct)
      return false;
   if(InpPortfolioDDStage1Scale <= 0.0 || InpPortfolioDDStage1Scale > 1.0 ||
      InpPortfolioDDStage2Scale <= 0.0 || InpPortfolioDDStage2Scale > InpPortfolioDDStage1Scale)
      return false;
   if(InpMinFVG_ATR <= 0.0 || InpMinBody_ATR <= 0.0 ||
      InpMinBodyRatio <= 0.0 || InpMinBodyRatio > 1.0)
      return false;
   if(InpReentryCloseThreshold <= 0.5 || InpReentryCloseThreshold >= 1.0)
      return false;
   if(InpSecondAttemptRiskScale <= 0.0 || InpSecondAttemptRiskScale > 1.0)
      return false;
   if(InpMaxZoneRiskBudgetPct <= 0.0)
      return false;
   return true;
}

int ResolveAssetMode()
{
   if(InpAssetMode == AUREON_GOLD) return 1;
   if(InpAssetMode == AUREON_BITCOIN) return 2;

   string s=_Symbol;
   StringToUpper(s);
   if(StringFind(s,"XAU") >= 0 || StringFind(s,"GOLD") >= 0) return 1;
   if(StringFind(s,"BTC") >= 0) return 2;
   return 0;
}

string AssetName()
{
   return g_asset == 1 ? "GOLD" : "BITCOIN";
}

ENUM_TIMEFRAMES EntryTF()
{
   return g_asset == 1 ? InpGoldEntryTF : InpBitcoinEntryTF;
}

ENUM_TIMEFRAMES RegimeTF()
{
   return g_asset == 1 ? InpGoldRegimeTF : InpBitcoinRegimeTF;
}

ENUM_TIMEFRAMES ContextTF1()
{
   return g_asset == 1 ? PERIOD_M5 : PERIOD_M15;
}

ENUM_TIMEFRAMES ContextTF2()
{
   return g_asset == 1 ? PERIOD_M15 : PERIOD_H1;
}

ENUM_TIMEFRAMES ContextTF3()
{
   return g_asset == 1 ? PERIOD_H1 : PERIOD_H4;
}

double BaseRiskPct()
{
   return g_asset == 1 ? InpGoldRiskPct : InpBitcoinRiskPct;
}

double DirectionRiskScale(bool bullish)
{
   if(g_asset == 1)
      return bullish ? InpGoldLongRiskScale : InpGoldShortRiskScale;
   return bullish ? InpBitcoinLongRiskScale : InpBitcoinShortRiskScale;
}

double MinQuality(bool bullish)
{
   if(g_asset == 1)
      return bullish ? InpGoldMinLongQuality : InpGoldMinShortQuality;
   return bullish ? InpBitcoinMinLongQuality : InpBitcoinMinShortQuality;
}

int MinAlignedVotes(bool bullish)
{
   if(g_asset == 1)
      return bullish ? InpGoldLongMinAlignedVotes : InpGoldShortMinAlignedVotes;
   return bullish ? InpBitcoinLongMinAlignedVotes : InpBitcoinShortMinAlignedVotes;
}

int MaxAttemptsPerFVG()
{
   return g_asset == 1 ? InpGoldMaxAttemptsPerFVG : InpBitcoinMaxAttemptsPerFVG;
}

int MaxTradesDay()
{
   return g_asset == 1 ? InpGoldMaxTradesDay : InpBitcoinMaxTradesDay;
}

double RewardRisk()
{
   return g_asset == 1 ? InpGoldRewardRisk : InpBitcoinRewardRisk;
}

int FixedMaxSpreadPoints()
{
   return g_asset == 1 ? InpGoldMaxSpreadPoints : InpBitcoinMaxSpreadPoints;
}

//+------------------------------------------------------------------+
//| FVG discovery                                                     |
//+------------------------------------------------------------------+
void ResetZone()
{
   g_zone.valid=false;
   g_zone.bullish=false;
   g_zone.low=0.0;
   g_zone.high=0.0;
   g_zone.formed=0;
   g_zone.attempts=0;
   g_zone.lastExitTime=0;
   g_zone.lastRealizedR=0.0;
   g_zone.lastRiskMoney=0.0;
   g_zone.gapATR=0.0;
   g_zone.bodyATR=0.0;
   g_zone.bodyRatio=0.0;
   g_zone.riskSpentPct=0.0;
   g_zone.quarantined=false;
}

void UpdateFVG()
{
   FVGZone newest;
   if(!FindNewestFVG(newest)) return;

   bool replace = !g_zone.valid || FVGExpired(g_zone) ||
                  (InpReplaceWithNewFVG && newest.formed > g_zone.formed);

   if(replace)
   {
      g_zone = newest;
      PersistZone();
   }
}

bool FindNewestFVG(FVGZone &z)
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

   MqlRates r[];
   double atr[];
   ArraySetAsSeries(r,true);
   ArraySetAsSeries(atr,true);

   int need=InpMaxFVG_Bars+5;
   if(need<30) need=30;
   if(CopyRates(_Symbol,g_entryTF,0,need,r)<6) return false;
   if(CopyBuffer(hATR,0,0,need,atr)<6) return false;

   for(int s=1; s<=InpMaxFVG_Bars && s+2<ArraySize(r); s++)
   {
      double a=atr[s];
      if(a<=0.0) continue;

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
      if(body<a*InpMinBody_ATR || body/range<InpMinBodyRatio) continue;

      if(oldHigh<newLow && mc>mo)
      {
         double gap=newLow-oldHigh;
         if(gap>=a*InpMinFVG_ATR)
         {
            z.valid=true; z.bullish=true;
            z.low=oldHigh; z.high=newLow; z.formed=r[s].time;
            z.gapATR=gap/a; z.bodyATR=body/a; z.bodyRatio=body/range;
            return true;
         }
      }

      if(oldLow>newHigh && mc<mo)
      {
         double gap=oldLow-newHigh;
         if(gap>=a*InpMinFVG_ATR)
         {
            z.valid=true; z.bullish=false;
            z.low=newHigh; z.high=oldLow; z.formed=r[s].time;
            z.gapATR=gap/a; z.bodyATR=body/a; z.bodyRatio=body/range;
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
   if(CopyRates(_Symbol,g_entryTF,0,3,r)<3) return false;

   double c=r[1].close;
   if(g_zone.bullish && c<g_zone.low) return false;
   if(!g_zone.bullish && c>g_zone.high) return false;
   return true;
}

bool FVGExpired(const FVGZone &z)
{
   if(!z.valid) return true;
   int sh=iBarShift(_Symbol,g_entryTF,z.formed,false);
   return sh<0 || sh>InpMaxFVG_Bars;
}

//+------------------------------------------------------------------+
//| Context                                                           |
//+------------------------------------------------------------------+
bool RefreshContext(bool bullish)
{
   if(!ReadRegime()) return false;

   int v1=ReadTrendVote(hTF1Fast,hTF1Slow);
   int v2=ReadTrendVote(hTF2Fast,hTF2Slow);
   int v3=ReadTrendVote(hTF3Fast,hTF3Slow);
   g_mtfScore=v1+v2+v3;

   if(!ReadMarketQuality()) return false;
   return true;
}

bool ReadRegime()
{
   double f[],s[],a[];
   ArrayResize(f,3); ArrayResize(s,3); ArrayResize(a,2);
   ArraySetAsSeries(f,true); ArraySetAsSeries(s,true); ArraySetAsSeries(a,true);

   if(CopyBuffer(hRegimeFast,0,0,3,f)<3) return false;
   if(CopyBuffer(hRegimeSlow,0,0,3,s)<3) return false;
   if(CopyBuffer(hADX,0,0,2,a)<2) return false;

   g_regimeFast=f[1];
   g_regimeSlow=s[1];
   g_regimeSlope=f[1]-f[2];
   g_regimeADX=a[1];
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

bool ReadMarketQuality()
{
   int need=InpVolatilityLookback+2;
   double atr[];
   ArraySetAsSeries(atr,true);
   if(CopyBuffer(hATR,0,0,need,atr)<need) return false;

   double currentATR=atr[1];
   if(currentATR<=0.0) return false;

   double sum=0.0;
   int count=0;
   for(int i=2;i<need;i++)
   {
      if(atr[i]>0.0){ sum+=atr[i]; count++; }
   }
   if(count<=0) return false;

   double meanATR=sum/(double)count;
   if(meanATR<=0.0) return false;
   g_atrRatio=currentATR/meanATR;

   int barsNeed=InpShockCooldownBars+2;
   if(barsNeed<3) barsNeed=3;
   MqlRates r[];
   ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,g_entryTF,0,barsNeed,r)<barsNeed) return false;

   g_shockRangeATR=0.0;
   for(int i=1;i<=InpShockCooldownBars && i<ArraySize(r);i++)
   {
      double ratio=(r[i].high-r[i].low)/currentATR;
      if(ratio>g_shockRangeATR) g_shockRangeATR=ratio;
   }

   if(g_atrRatio<InpMinATRRatio || g_atrRatio>InpMaxATRRatio)
      return false;
   if(InpUseShockGuard && g_shockRangeATR>InpMaxClosedBarRangeATR)
      return false;

   return true;
}

double ComputeEntryQualityScore(bool bullish)
{
   double score=0.0;

   if(g_zone.gapATR>=InpMinFVG_ATR) score+=10.0;
   if(g_zone.gapATR>=0.25) score+=5.0;
   if(g_zone.gapATR>=0.40) score+=5.0;

   if(g_zone.bodyATR>=InpMinBody_ATR) score+=10.0;
   if(g_zone.bodyATR>=0.80) score+=5.0;
   if(g_zone.bodyATR>=1.20) score+=5.0;

   if(g_zone.bodyRatio>=InpMinBodyRatio) score+=10.0;
   if(g_zone.bodyRatio>=0.70) score+=5.0;
   if(g_zone.bodyRatio>=0.80) score+=5.0;

   int aligned=bullish?g_mtfScore:-g_mtfScore;
   if(aligned<0) aligned=0;
   score+=5.0*(double)aligned;

   bool regimeAligned=bullish?(g_regimeFast>g_regimeSlow):(g_regimeFast<g_regimeSlow);
   bool slopeAligned=bullish?(g_regimeSlope>0.0):(g_regimeSlope<0.0);
   if(regimeAligned) score+=5.0;
   if(slopeAligned) score+=5.0;

   if(g_regimeADX>=InpMinADX) score+=5.0;
   if(g_regimeADX>=25.0) score+=5.0;

   if(g_atrRatio>=0.60 && g_atrRatio<=1.50) score+=5.0;
   if(g_spreadRatio<=1.50) score+=5.0;

   if(score>100.0) score=100.0;
   if(score<0.0) score=0.0;
   return score;
}

bool DirectionalQualityAllows(bool bullish)
{
   int aligned=bullish?g_mtfScore:-g_mtfScore;
   if(aligned<MinAlignedVotes(bullish))
      return false;
   if(g_qualityScore<MinQuality(bullish))
      return false;
   return true;
}

//+------------------------------------------------------------------+
//| Re-entry                                                          |
//+------------------------------------------------------------------+
bool ReentryAllows(bool bullish)
{
   if(!InpUseControlledReentry)
      return g_zone.attempts<MaxAttemptsPerFVG();

   if(g_zone.quarantined || g_zone.attempts>=MaxAttemptsPerFVG())
      return false;
   if(g_zone.attempts<=0)
      return true;
   if(g_zone.lastExitTime<=0)
      return false;
   if(!InpAllowReentryAfterProfit && g_zone.lastRealizedR>0.0)
      return false;
   if(BarsSince(g_zone.lastExitTime)<InpReentryCooldownBars)
      return false;

   if(InpRequireClosedBarRejectionOnReentry &&
      !ClosedBarRejectionForReentry(bullish,InpReentryCloseThreshold))
      return false;

   if(g_zone.riskSpentPct>=InpMaxZoneRiskBudgetPct-1e-8)
      return false;

   return true;
}

int BarsSince(datetime t)
{
   if(t<=0) return 1000000;
   int sh=iBarShift(_Symbol,g_entryTF,t,false);
   return sh<0 ? 0 : sh;
}

bool ClosedBarRejectionForReentry(bool bullish,double threshold)
{
   MqlRates r[];
   ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,g_entryTF,0,3,r)<3) return false;
   if(g_zone.lastExitTime>0 && r[1].time<=g_zone.lastExitTime) return false;

   double range=r[1].high-r[1].low;
   if(range<=0.0) return false;
   bool touched=(r[1].low<=g_zone.high && r[1].high>=g_zone.low);
   if(!touched) return false;

   double closePos=(r[1].close-r[1].low)/range;
   if(bullish)
      return r[1].close>r[1].open && closePos>=threshold;
   return r[1].close<r[1].open && closePos<=(1.0-threshold);
}

//+------------------------------------------------------------------+
//| Entry                                                             |
//+------------------------------------------------------------------+
void TryFVGEntry()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;
   if(tick.bid<=0.0 || tick.ask<=0.0) return;

   double midpoint=(g_zone.low+g_zone.high)/2.0;

   if(g_zone.bullish)
   {
      if(tick.ask<g_zone.low || tick.ask>g_zone.high) return;
      if(InpRequireMidpoint && tick.ask>midpoint) return;
      if(InpRequireRejection && !BullishRejection()) return;
      OpenTrade(true,g_zone);
   }
   else
   {
      if(tick.bid<g_zone.low || tick.bid>g_zone.high) return;
      if(InpRequireMidpoint && tick.bid<midpoint) return;
      if(InpRequireRejection && !BearishRejection()) return;
      OpenTrade(false,g_zone);
   }
}

bool BullishRejection()
{
   MqlRates r[];
   ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,g_entryTF,0,2,r)<2) return false;

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double range=r[0].high-r[0].low;
   if(range<=0.0) return false;
   return (bid-r[0].low)/range>=0.55;
}

bool BearishRejection()
{
   MqlRates r[];
   ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,g_entryTF,0,2,r)<2) return false;

   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double range=r[0].high-r[0].low;
   if(range<=0.0) return false;
   return (ask-r[0].low)/range<=0.45;
}

bool OpenTrade(bool bullish,const FVGZone &z)
{
   double atr=GetATR();
   if(atr<=0.0) return false;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;
   double entry=bullish?tick.ask:tick.bid;
   if(entry<=0.0) return false;

   double sl=bullish ? z.low-atr*InpSL_ATR_Buffer : z.high+atr*InpSL_ATR_Buffer;
   double riskDist=MathAbs(entry-sl);
   if(riskDist<=0.0 || riskDist>atr*InpMaxSL_ATR)
      return false;

   double tp=bullish ? entry+riskDist*RewardRisk() : entry-riskDist*RewardRisk();
   sl=NormalizePrice(sl);
   tp=NormalizePrice(tp);
   if(!StopsAreValid(entry,sl,tp,bullish)) return false;

   int nextAttempt=g_zone.attempts+1;
   double attemptScale=(nextAttempt<=1)?1.0:InpSecondAttemptRiskScale;
   double ddScale=PortfolioRiskScale();
   double dirScale=DirectionRiskScale(bullish);
   double combinedScale=attemptScale*ddScale*dirScale;
   if(combinedScale<=0.0) return false;

   double remainingZoneRisk=InpMaxZoneRiskBudgetPct-g_zone.riskSpentPct;
   if(remainingZoneRisk<=0.0) return false;

   double volume=0.0;
   double riskMoney=0.0;
   double riskPct=0.0;
   if(!CalculateVolume(entry,sl,bullish,combinedScale,remainingZoneRisk,volume,riskMoney,riskPct))
      return false;

   if(!MarginPreflight(bullish,volume,entry))
      return false;

   bool ok=bullish ? trade.Buy(volume,_Symbol,0.0,sl,tp,"AUREON PRIME GOLD/BTC")
                   : trade.Sell(volume,_Symbol,0.0,sl,tp,"AUREON PRIME GOLD/BTC");
   if(!ok)
   {
      Print("AUREON trade failed: ",trade.ResultRetcodeDescription());
      return false;
   }

   uint rc=trade.ResultRetcode();
   if(rc!=TRADE_RETCODE_DONE && rc!=TRADE_RETCODE_DONE_PARTIAL && rc!=TRADE_RETCODE_PLACED)
   {
      Print("AUREON trade rejected: ",trade.ResultRetcodeDescription());
      return false;
   }

   g_zone.attempts++;
   g_zone.lastRiskMoney=riskMoney;
   g_zone.riskSpentPct+=riskPct;
   PersistZone();

   WriteTelemetry("ENTRY",0.0,0.0,riskPct,volume);

   if(InpVerboseLog)
      Print("AUREON entry | ",_Symbol,
            " dir=",bullish?"BUY":"SELL",
            " q=",DoubleToString(g_qualityScore,1),
            " mtf=",g_mtfScore,
            " risk%=",DoubleToString(riskPct,3),
            " vol=",DoubleToString(volume,4),
            " attempt=",g_zone.attempts);

   return true;
}

bool CalculateVolume(double entry,double sl,bool bullish,double scale,double zoneRemainingPct,
                     double &volume,double &riskMoney,double &riskPct)
{
   volume=0.0;
   riskMoney=0.0;
   riskPct=0.0;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity<=0.0 || scale<=0.0) return false;

   double targetPct=BaseRiskPct()*scale;
   if(targetPct>zoneRemainingPct) targetPct=zoneRemainingPct;
   if(targetPct<=0.0) return false;

   double oneLotLoss=0.0;
   ENUM_ORDER_TYPE type=bullish?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type,_Symbol,1.0,entry,sl,oneLotLoss))
      return false;

   oneLotLoss=MathAbs(oneLotLoss);
   if(oneLotLoss<=0.0) return false;

   double targetMoney=equity*targetPct/100.0;
   double raw=targetMoney/oneLotLoss;

   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(minLot<=0.0 || maxLot<=0.0 || step<=0.0) return false;

   volume=MathFloor(raw/step)*step;
   if(volume>maxLot) volume=maxLot;
   volume=NormalizeVolume(volume);
   if(volume<minLot) return false;

   double calcLoss=0.0;
   if(!OrderCalcProfit(type,_Symbol,volume,entry,sl,calcLoss))
      return false;

   riskMoney=MathAbs(calcLoss);
   riskPct=riskMoney/equity*100.0;

   if(riskPct>targetPct+1e-6)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Position management                                               |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   ulong ticket=GetOurPositionTicket();
   if(ticket==0 || !PositionSelectByTicket(ticket)) return;

   long type=PositionGetInteger(POSITION_TYPE);
   double open=PositionGetDouble(POSITION_PRICE_OPEN);
   double sl=PositionGetDouble(POSITION_SL);
   double tp=PositionGetDouble(POSITION_TP);
   double price=(type==POSITION_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   if(open<=0.0 || price<=0.0 || tp<=0.0 || RewardRisk()<=0.0) return;

   double initialRisk=MathAbs(tp-open)/RewardRisk();
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
         double newSL=(type==POSITION_TYPE_BUY)?open+initialRisk*lockRR:open-initialRisk*lockRR;
         newSL=NormalizePrice(newSL);
         if(IsBetterSL(type,sl,newSL) && StopsAreValid(price,newSL,tp,type==POSITION_TYPE_BUY))
         {
            if(SafeModifyPosition(ticket,newSL,tp,"LOCK"))
               sl=newSL;
         }
      }
   }

   if(!InpUseSmartTrail || rr<InpTrailStartRR) return;

   double atr=GetATR();
   if(atr<=0.0) return;

   double trailATR=(rr>=InpTrailTightenRR)?InpTrailTightATR:InpTrailATR;
   double newSL=(type==POSITION_TYPE_BUY)?price-atr*trailATR:price+atr*trailATR;
   double floorSL=(type==POSITION_TYPE_BUY)?open+initialRisk*InpTrailFloorRR:open-initialRisk*InpTrailFloorRR;

   if(type==POSITION_TYPE_BUY) newSL=MathMax(newSL,floorSL);
   else newSL=MathMin(newSL,floorSL);

   newSL=NormalizePrice(newSL);
   if(IsBetterSL(type,sl,newSL) && StopsAreValid(price,newSL,tp,type==POSITION_TYPE_BUY))
      SafeModifyPosition(ticket,newSL,tp,"TRAIL");
}

bool SafeModifyPosition(ulong ticket,double newSL,double tp,string reason)
{
   ResetLastError();
   bool ok=trade.PositionModify(ticket,newSL,tp);
   uint rc=trade.ResultRetcode();

   if(!ok || (rc!=TRADE_RETCODE_DONE && rc!=TRADE_RETCODE_NO_CHANGES && rc!=TRADE_RETCODE_PLACED))
   {
      Print("AUREON modify failed [",reason,"] rc=",rc," ",trade.ResultRetcodeDescription(),
            " err=",GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Trading permissions / portfolio governor                          |
//+------------------------------------------------------------------+
bool TradingAllowed()
{
   if(!InpExecutionArmed) return false;

   if(InpDemoOnly && (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)!=ACCOUNT_TRADE_MODE_DEMO)
      return false;

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;
   if(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE)!=SYMBOL_TRADE_MODE_FULL) return false;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;
   if(tick.bid<=0.0 || tick.ask<=0.0 || tick.time<=0) return false;
   if(InpMaxTickAgeSeconds>0 && (TimeCurrent()-tick.time)>InpMaxTickAgeSeconds) return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   if((dt.day_of_week==0 || dt.day_of_week==6) && g_asset!=2)
      return false;
   if((dt.day_of_week==0 || dt.day_of_week==6) && g_asset==2 && !InpBitcoinAllowWeekend)
      return false;

   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0.0) return false;
   double spread=(tick.ask-tick.bid)/point;

   int fixedMax=FixedMaxSpreadPoints();
   if(fixedMax>0 && spread>fixedMax) return false;

   if(InpUseRelativeSpreadGuard && g_spreadSamples>=InpSpreadEMAWarmupTicks &&
      g_spreadEMA>0.0 && spread>g_spreadEMA*InpRelativeSpreadMultiplier)
      return false;

   if(PortfolioDailyLossPct()>=InpPortfolioDailyLossPct)
      return false;
   if(PortfolioDrawdownPct()>=InpPortfolioHardStopDDPct)
      return false;

   return true;
}

double PortfolioRiskScale()
{
   double dd=PortfolioDrawdownPct();
   if(dd>=InpPortfolioHardStopDDPct) return 0.0;
   if(dd>=InpPortfolioDDStage2Pct) return InpPortfolioDDStage2Scale;
   if(dd>=InpPortfolioDDStage1Pct) return InpPortfolioDDStage1Scale;
   return 1.0;
}

bool MarginPreflight(bool bullish,double volume,double entry)
{
   ENUM_ORDER_TYPE type=bullish?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double required=0.0;
   if(!OrderCalcMargin(type,_Symbol,volume,entry,required)) return false;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double margin=AccountInfoDouble(ACCOUNT_MARGIN);
   double free=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(equity<=0.0 || free<=0.0 || required>free) return false;

   if(InpMaxSingleTradeMarginPct>0.0 && required/equity*100.0>InpMaxSingleTradeMarginPct)
      return false;

   double projected=margin+required;
   if(projected>0.0 && InpMinProjectedMarginLevelPct>0.0)
   {
      double level=equity/projected*100.0;
      if(level<InpMinProjectedMarginLevelPct)
         return false;
   }
   return true;
}

void UpdateSpreadState()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   double p=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(p<=0.0 || tick.bid<=0.0 || tick.ask<=0.0) return;

   double spread=(tick.ask-tick.bid)/p;
   if(spread<0.0) return;

   double alpha=2.0/((double)InpSpreadEMAWarmupTicks+1.0);
   if(g_spreadSamples<=0 || g_spreadEMA<=0.0)
      g_spreadEMA=spread;
   else
      g_spreadEMA=g_spreadEMA+alpha*(spread-g_spreadEMA);

   g_spreadSamples++;
   g_spreadRatio=(g_spreadEMA>0.0)?spread/g_spreadEMA:1.0;
}

//+------------------------------------------------------------------+
//| Shared account state                                              |
//+------------------------------------------------------------------+
string AccountPrefix()
{
   return StringFormat("AP3_%I64d_",AccountInfoInteger(ACCOUNT_LOGIN));
}

string ZonePrefix()
{
   string s=_Symbol;
   StringReplace(s,".","_");
   StringReplace(s,"#","_");
   StringReplace(s,"-","_");
   return AccountPrefix()+s+"_"+IntegerToString((int)g_asset)+"_";
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
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   int day=TodayKey();

   if(!GlobalVariableCheck(p+"DAY_KEY") || (int)GlobalVariableGet(p+"DAY_KEY")!=day)
   {
      GlobalVariableSet(p+"DAY_KEY",(double)day);
      GlobalVariableSet(p+"DAY_EQ",eq);
   }
   else if(!GlobalVariableCheck(p+"DAY_EQ"))
      GlobalVariableSet(p+"DAY_EQ",eq);

   if(!GlobalVariableCheck(p+"EQ_PEAK"))
      GlobalVariableSet(p+"EQ_PEAK",eq);
}

void UpdatePortfolioPeak()
{
   string key=AccountPrefix()+"EQ_PEAK";
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq<=0.0) return;

   double peak=GlobalVariableCheck(key)?GlobalVariableGet(key):eq;
   if(eq>peak)
      GlobalVariableSet(key,eq);
}

double PortfolioDailyLossPct()
{
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   string key=AccountPrefix()+"DAY_EQ";
   if(!GlobalVariableCheck(key)) return 0.0;

   double start=GlobalVariableGet(key);
   if(start<=0.0 || eq>=start) return 0.0;
   return (start-eq)/start*100.0;
}

double PortfolioDrawdownPct()
{
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   string key=AccountPrefix()+"EQ_PEAK";
   if(!GlobalVariableCheck(key)) return 0.0;

   double peak=GlobalVariableGet(key);
   if(peak<=0.0 || eq>=peak) return 0.0;
   return (peak-eq)/peak*100.0;
}

//+------------------------------------------------------------------+
//| Persistence                                                       |
//+------------------------------------------------------------------+
void PersistZone()
{
   if(InpPersistState)
      SaveZoneState();
}

void SaveZoneState()
{
   string p=ZonePrefix();
   GlobalVariableSet(p+"VALID",g_zone.valid?1.0:0.0);
   GlobalVariableSet(p+"BULL",g_zone.bullish?1.0:0.0);
   GlobalVariableSet(p+"LOW",g_zone.low);
   GlobalVariableSet(p+"HIGH",g_zone.high);
   GlobalVariableSet(p+"FORMED",(double)g_zone.formed);
   GlobalVariableSet(p+"ATT",(double)g_zone.attempts);
   GlobalVariableSet(p+"LAST_EXIT",(double)g_zone.lastExitTime);
   GlobalVariableSet(p+"LAST_R",g_zone.lastRealizedR);
   GlobalVariableSet(p+"LAST_RISK",g_zone.lastRiskMoney);
   GlobalVariableSet(p+"GAP",g_zone.gapATR);
   GlobalVariableSet(p+"BODY",g_zone.bodyATR);
   GlobalVariableSet(p+"RATIO",g_zone.bodyRatio);
   GlobalVariableSet(p+"RISK_USED",g_zone.riskSpentPct);
   GlobalVariableSet(p+"QUAR",g_zone.quarantined?1.0:0.0);
}

void LoadZoneState()
{
   string p=ZonePrefix();
   if(!GlobalVariableCheck(p+"VALID")) return;

   g_zone.valid=GlobalVariableGet(p+"VALID")>0.5;
   g_zone.bullish=GlobalVariableCheck(p+"BULL") && GlobalVariableGet(p+"BULL")>0.5;
   g_zone.low=GlobalVariableCheck(p+"LOW")?GlobalVariableGet(p+"LOW"):0.0;
   g_zone.high=GlobalVariableCheck(p+"HIGH")?GlobalVariableGet(p+"HIGH"):0.0;
   g_zone.formed=GlobalVariableCheck(p+"FORMED")?(datetime)GlobalVariableGet(p+"FORMED"):0;
   g_zone.attempts=GlobalVariableCheck(p+"ATT")?(int)GlobalVariableGet(p+"ATT"):0;
   g_zone.lastExitTime=GlobalVariableCheck(p+"LAST_EXIT")?(datetime)GlobalVariableGet(p+"LAST_EXIT"):0;
   g_zone.lastRealizedR=GlobalVariableCheck(p+"LAST_R")?GlobalVariableGet(p+"LAST_R"):0.0;
   g_zone.lastRiskMoney=GlobalVariableCheck(p+"LAST_RISK")?GlobalVariableGet(p+"LAST_RISK"):0.0;
   g_zone.gapATR=GlobalVariableCheck(p+"GAP")?GlobalVariableGet(p+"GAP"):0.0;
   g_zone.bodyATR=GlobalVariableCheck(p+"BODY")?GlobalVariableGet(p+"BODY"):0.0;
   g_zone.bodyRatio=GlobalVariableCheck(p+"RATIO")?GlobalVariableGet(p+"RATIO"):0.0;
   g_zone.riskSpentPct=GlobalVariableCheck(p+"RISK_USED")?GlobalVariableGet(p+"RISK_USED"):0.0;
   g_zone.quarantined=GlobalVariableCheck(p+"QUAR") && GlobalVariableGet(p+"QUAR")>0.5;

   if(g_zone.valid && FVGExpired(g_zone))
      g_zone.valid=false;
}

//+------------------------------------------------------------------+
//| Telemetry                                                         |
//+------------------------------------------------------------------+
void EnsureTelemetryHeader()
{
   int h=FileOpen(InpTelemetryFile,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(h==INVALID_HANDLE) return;

   if(FileSize(h)==0)
      FileWrite(h,"event","time","symbol","asset","magic","direction","zone_formed",
                   "attempts","gap_atr","body_atr","body_ratio","mtf_score","quality",
                   "atr_ratio","spread_ratio","portfolio_daily_loss_pct","portfolio_dd_pct",
                   "risk_pct","volume","realized_r","net");

   FileClose(h);
}

void WriteTelemetry(string eventName,double realizedR,double net,double riskPct,double volume)
{
   if(!InpEnableTelemetry) return;

   int h=FileOpen(InpTelemetryFile,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(h==INVALID_HANDLE) return;

   FileSeek(h,0,SEEK_END);
   string direction=g_zone.bullish?"BUY":"SELL";
   FileWrite(h,eventName,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
             _Symbol,AssetName(),(long)g_magic,direction,
             TimeToString(g_zone.formed,TIME_DATE|TIME_SECONDS),
             g_zone.attempts,DoubleToString(g_zone.gapATR,4),
             DoubleToString(g_zone.bodyATR,4),DoubleToString(g_zone.bodyRatio,4),
             g_mtfScore,DoubleToString(g_qualityScore,2),DoubleToString(g_atrRatio,4),
             DoubleToString(g_spreadRatio,4),DoubleToString(PortfolioDailyLossPct(),3),
             DoubleToString(PortfolioDrawdownPct(),3),DoubleToString(riskPct,4),
             DoubleToString(volume,4),DoubleToString(realizedR,4),DoubleToString(net,2));
   FileClose(h);
}

//+------------------------------------------------------------------+
//| Position / history helpers                                        |
//+------------------------------------------------------------------+
bool HasOurPosition()
{
   return GetOurPositionTicket()!=0;
}

ulong GetOurPositionTicket()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)==g_magic)
         return t;
   }
   return 0;
}

int CountOpenPositionsAll()
{
   return PositionsTotal();
}

int CountTodayEntries()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   dt.hour=0; dt.min=0; dt.sec=0;

   datetime from=StructToTime(dt);
   datetime to=TimeCurrent();
   if(!HistorySelect(from,to)) return 0;

   int count=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(d==0) continue;
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol) continue;
      if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=g_magic) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY)==DEAL_ENTRY_IN)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Utility                                                           |
//+------------------------------------------------------------------+
double GetATR()
{
   double v[];
   ArrayResize(v,2);
   ArraySetAsSeries(v,true);
   if(CopyBuffer(hATR,0,0,2,v)<2) return 0.0;
   return v[1];
}

bool IsNewBar()
{
   datetime t=iTime(_Symbol,g_entryTF,0);
   if(t==0) return false;
   if(t!=g_lastBar)
   {
      g_lastBar=t;
      return true;
   }
   return false;
}

bool StopsAreValid(double price,double sl,double tp,bool bullish)
{
   double p=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(p<=0.0) return false;

   long st=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long fr=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist=MathMax(st,fr)*p;

   if(bullish)
      return sl<price && tp>price && price-sl>=minDist && tp-price>=minDist;
   return sl>price && tp<price && sl-price>=minDist && price-tp>=minDist;
}

bool IsBetterSL(long type,double oldSL,double newSL)
{
   if(type==POSITION_TYPE_BUY) return oldSL==0.0 || newSL>oldSL;
   return oldSL==0.0 || newSL<oldSL;
}

double NormalizePrice(double price)
{
   return NormalizeDouble(price,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
}

double NormalizeVolume(double volume)
{
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
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
//+------------------------------------------------------------------+
