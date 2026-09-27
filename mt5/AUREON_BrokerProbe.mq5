//+------------------------------------------------------------------+
//| AUREON_BrokerProbe.mq5                                            |
//| Read-only broker/symbol capability probe for MT5 demo validation  |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs
#property version "1.20"

input string InpOutputFile = "AUREON_BROKER_PROBE.csv";

bool WaitForSymbolData(string symbol,int timeoutMs)
{
   if(!SymbolSelect(symbol,true))
      return false;

   int waited=0;
   while(waited<timeoutMs)
   {
      MqlTick tick;
      ZeroMemory(tick);
      bool synced=SymbolIsSynchronized(symbol);
      bool haveTick=SymbolInfoTick(symbol,tick) && tick.time_msc>0;
      if(synced && haveTick)
         return true;

      Sleep(100);
      waited+=100;
   }

   return SymbolIsSynchronized(symbol);
}

bool RelevantSymbol(string symbol)
{
   string s=symbol;
   StringToUpper(s);
   return StringFind(s,"XAU")>=0 || StringFind(s,"GOLD")>=0 || StringFind(s,"BTC")>=0;
}

string SessionSummary(string symbol,ENUM_DAY_OF_WEEK day)
{
   string out="";
   datetime from=0,to=0;
   for(uint i=0;i<16;i++)
   {
      if(!SymbolInfoSessionTrade(symbol,day,i,from,to))
         break;

      if(StringLen(out)>0) out+=";";
      out+=TimeToString(from,TIME_MINUTES)+"-"+TimeToString(to,TIME_MINUTES);
   }
   return out;
}

void OnStart()
{
   int h=FileOpen(InpOutputFile,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(h==INVALID_HANDLE)
   {
      Print("AUREON BrokerProbe FileOpen failed: ",GetLastError());
      return;
   }

   FileWrite(h,
      "account_trade_mode","account_currency","account_leverage","server",
      "symbol","synchronized","digits","point","tick_size","tick_value",
      "contract_size","volume_min","volume_step","volume_max",
      "calc_profit_currency","calc_mode","calc_1tick_buy_profit","calc_1tick_sell_profit","calc_margin_buy_1lot",
      "stops_level","freeze_level","trade_mode","spread_float","spread_points",
      "swap_long","swap_short","bid","ask","quote_time",
      "sun_sessions","mon_sessions","tue_sessions","wed_sessions",
      "thu_sessions","fri_sessions","sat_sessions");

   string server=AccountInfoString(ACCOUNT_SERVER);
   string currency=AccountInfoString(ACCOUNT_CURRENCY);
   long accountMode=AccountInfoInteger(ACCOUNT_TRADE_MODE);
   long leverage=AccountInfoInteger(ACCOUNT_LEVERAGE);

   int total=SymbolsTotal(false);
   int matches=0;

   for(int i=0;i<total;i++)
   {
      string sym=SymbolName(i,false);
      if(!RelevantSymbol(sym))
         continue;

      bool synchronized=WaitForSymbolData(sym,2500);
      MqlTick tick;
      ZeroMemory(tick);
      SymbolInfoTick(sym,tick);

      double tickSize=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
      double buyTickProfit=0.0;
      double sellTickProfit=0.0;
      double buyMargin=0.0;

      if(tick.ask>0.0 && tickSize>0.0)
         OrderCalcProfit(ORDER_TYPE_BUY,sym,1.0,tick.ask,tick.ask+tickSize,buyTickProfit);
      if(tick.bid>0.0 && tickSize>0.0)
         OrderCalcProfit(ORDER_TYPE_SELL,sym,1.0,tick.bid,tick.bid-tickSize,sellTickProfit);
      if(tick.ask>0.0)
         OrderCalcMargin(ORDER_TYPE_BUY,sym,1.0,tick.ask,buyMargin);

      FileWrite(h,
         accountMode,currency,leverage,server,
         sym,(synchronized?"TRUE":"FALSE"),
         (int)SymbolInfoInteger(sym,SYMBOL_DIGITS),
         DoubleToString(SymbolInfoDouble(sym,SYMBOL_POINT),10),
         DoubleToString(SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE),10),
         DoubleToString(SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE),10),
         DoubleToString(SymbolInfoDouble(sym,SYMBOL_TRADE_CONTRACT_SIZE),4),
         DoubleToString(SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN),4),
         DoubleToString(SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP),4),
         DoubleToString(SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX),4),
         SymbolInfoString(sym,SYMBOL_CURRENCY_PROFIT),
         (long)SymbolInfoInteger(sym,SYMBOL_TRADE_CALC_MODE),
         DoubleToString(buyTickProfit,10),
         DoubleToString(sellTickProfit,10),
         DoubleToString(buyMargin,6),
         (long)SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL),
         (long)SymbolInfoInteger(sym,SYMBOL_TRADE_FREEZE_LEVEL),
         (long)SymbolInfoInteger(sym,SYMBOL_TRADE_MODE),
         (long)SymbolInfoInteger(sym,SYMBOL_SPREAD_FLOAT),
         (long)SymbolInfoInteger(sym,SYMBOL_SPREAD),
         DoubleToString(SymbolInfoDouble(sym,SYMBOL_SWAP_LONG),6),
         DoubleToString(SymbolInfoDouble(sym,SYMBOL_SWAP_SHORT),6),
         DoubleToString(tick.bid,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS)),
         DoubleToString(tick.ask,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS)),
         TimeToString((datetime)tick.time,TIME_DATE|TIME_SECONDS),
         SessionSummary(sym,SUNDAY),
         SessionSummary(sym,MONDAY),
         SessionSummary(sym,TUESDAY),
         SessionSummary(sym,WEDNESDAY),
         SessionSummary(sym,THURSDAY),
         SessionSummary(sym,FRIDAY),
         SessionSummary(sym,SATURDAY));

      matches++;
   }

   FileClose(h);
   Print("AUREON BrokerProbe complete. Relevant symbols=",matches," file=",InpOutputFile);
}
//+------------------------------------------------------------------+
