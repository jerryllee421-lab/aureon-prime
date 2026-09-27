using Aureon.Core;

var engine = new RiskEngine();
var policy = RiskPolicy.Conservative;
var healthy = new MarketRiskState(
    Balance: 10_000,
    Equity: 10_000,
    DailyLossPercent: 0,
    DrawdownPercent: 0,
    OpenPositions: 0,
    ConsecutiveLosses: 0,
    EmergencyHalt: false);

var failures = new List<string>();

Check(
    engine.Evaluate(new TradeIntent(TradeSide.Buy, 4300, 4290, 4320, "valid-buy"), policy, healthy).Allowed,
    "Valid 2R buy should pass.");

Check(
    !engine.Evaluate(new TradeIntent(TradeSide.Buy, 4300, 4290, 4310, "low-rr"), policy, healthy).Allowed,
    "1R buy must be blocked.");

Check(
    !engine.Evaluate(
        new TradeIntent(TradeSide.Buy, 4300, 4290, 4320, "daily-limit"),
        policy,
        healthy with { DailyLossPercent = 2.0 }).Allowed,
    "Daily loss limit must block.");

Check(
    !engine.Evaluate(
        new TradeIntent(TradeSide.Sell, 4300, 4310, 4280, "position-limit"),
        policy,
        healthy with { OpenPositions = 1 }).Allowed,
    "Open-position limit must block.");

Check(
    !engine.Evaluate(
        new TradeIntent(TradeSide.Buy, 4300, 4310, 4320, "bad-geometry"),
        policy,
        healthy).Allowed,
    "Invalid buy stop geometry must block.");

Check(
    !engine.Evaluate(
        new TradeIntent(TradeSide.Buy, 4300, 4290, 4320, "halt"),
        policy,
        healthy with { EmergencyHalt = true }).Allowed,
    "Emergency halt must block.");

Check(
    Math.Abs(RiskEngine.CalculateRiskAmount(10_000, 0.5) - 50.0) < 0.0001,
    "0.5% of 10,000 must equal 50.");

if (failures.Count > 0)
{
    Console.Error.WriteLine("AUREON CORE SAFETY TESTS FAILED");
    foreach (var failure in failures)
        Console.Error.WriteLine($"- {failure}");
    return 1;
}

Console.WriteLine("AUREON CORE SAFETY TESTS PASSED");
return 0;

void Check(bool condition, string message)
{
    if (!condition)
        failures.Add(message);
}
