//+------------------------------------------------------------------+
//| AUREON_TradePreflight.mq5                                         |
//| Zero-order server validation for the approved MT5 demo account    |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs
#property version "1.00"

input string InpGoldSymbol = "XAUUSD";
input string InpBitcoinSymbol = "BTCUSDT";
input string InpOutputFile = "AUREON_TRADE_PREFLIGHT.csv";
input int InpSyncTimeoutMs = 5000;
input int InpDeviationPoints = 100;
input ulong InpMagic = 26094888;

bool WaitForSymbolData(string symbol,int timeoutMs)
{
   if(!SymbolSelect(symbol,true))
      return false;

   int waited=0;
   while(waited<timeoutMs)
   {
      MqlTick tick;
      ZeroMemory(tick);
      if(SymbolIsSynchronized(symbol) &&
         SymbolInfoTick(symbol,tick) &&
         tick.time_msc>0 &&
         tick.bid>0.0 &&
         tick.ask>0.0)
         return true;

      Sleep(100);
      waited+=100;
   }

   return false;
}

ENUM_ORDER_TYPE_FILLING PreferredFilling(string symbol)
{
   long mode=SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);

   if((mode & SYMBOL_FILLING_FOK)==SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;

   if((mode & SYMBOL_FILLING_IOC)==SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;
}

void CheckSide(int h,string symbol,bool bullish)
{
   MqlTick tick;
   ZeroMemory(tick);

   bool synced=WaitForSymbolData(symbol,InpSyncTimeoutMs);
   bool haveTick=SymbolInfoTick(symbol,tick);

   double volume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   if(volume<=0.0)
      volume=0.01;

   MqlTradeRequest request={};
   MqlTradeCheckResult check={};

   request.action=TRADE_ACTION_DEAL;
   request.symbol=symbol;
   request.volume=volume;
   request.type=bullish?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   request.price=bullish?tick.ask:tick.bid;
   request.deviation=InpDeviationPoints;
   request.magic=InpMagic;
   request.type_filling=PreferredFilling(symbol);

   ResetLastError();
   bool ok=false;
   int terminalError=0;

   if(synced && haveTick && request.price>0.0)
   {
      ok=OrderCheck(request,check);
      terminalError=GetLastError();
   }

   FileWrite(h,
      symbol,
      bullish?"BUY":"SELL",
      (synced?"TRUE":"FALSE"),
      (long)SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE),
      (long)AccountInfoInteger(ACCOUNT_TRADE_MODE),
      (long)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED),
      (long)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED),
      (long)MQLInfoInteger(MQL_TRADE_ALLOWED),
      DoubleToString(volume,4),
      DoubleToString(request.price,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS)),
      (ok?"TRUE":"FALSE"),
      (long)check.retcode,
      check.comment,
      terminalError,
      DoubleToString(check.balance,2),
      DoubleToString(check.equity,2),
      DoubleToString(check.profit,2),
      DoubleToString(check.margin,2),
      DoubleToString(check.margin_free,2),
      DoubleToString(check.margin_level,2),
      SymbolInfoString(symbol,SYMBOL_CURRENCY_PROFIT),
      (long)SymbolInfoInteger(symbol,SYMBOL_TRADE_CALC_MODE));
}

void OnStart()
{
   int h=FileOpen(InpOutputFile,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(h==INVALID_HANDLE)
   {
      Print("AUREON TradePreflight FileOpen failed: ",GetLastError());
      return;
   }

   FileWrite(h,
      "symbol","side","synchronized","symbol_trade_mode",
      "account_trade_mode","account_trade_allowed","terminal_trade_allowed","mql_trade_allowed",
      "volume","price","ordercheck_ok","check_retcode","check_comment","terminal_error",
      "balance_after","equity_after","profit_after","margin_after","margin_free_after",
      "margin_level_after","profit_currency","calc_mode");

   CheckSide(h,InpGoldSymbol,true);
   CheckSide(h,InpGoldSymbol,false);
   CheckSide(h,InpBitcoinSymbol,true);
   CheckSide(h,InpBitcoinSymbol,false);

   FileClose(h);

   int marker=FileOpen("AUREON_TRADE_PREFLIGHT_STATUS.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(marker!=INVALID_HANDLE)
   {
      FileWrite(marker,"ORDER_CHECK_ONLY");
      FileWrite(marker,"NO_ORDERS_SENT");
      FileClose(marker);
   }

   Print("AUREON TradePreflight complete. No orders were sent.");
}
//+------------------------------------------------------------------+
