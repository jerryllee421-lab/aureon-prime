namespace Aureon.Core;

public enum TradeSide
{
    Buy = 1,
    Sell = -1
}

public sealed record TradeIntent(
    TradeSide Side,
    double Entry,
    double StopLoss,
    double TakeProfit,
    string SetupId);

public sealed record RiskPolicy(
    double RiskPercent,
    double MinimumRewardRisk,
    double DailyLossLimitPercent,
    double MaxDrawdownPercent,
    int MaxOpenPositions,
    int MaxConsecutiveLosses)
{
    public static RiskPolicy Conservative => new(
        RiskPercent: 0.50,
        MinimumRewardRisk: 1.80,
        DailyLossLimitPercent: 2.00,
        MaxDrawdownPercent: 8.00,
        MaxOpenPositions: 1,
        MaxConsecutiveLosses: 2);
}

public sealed record MarketRiskState(
    double Balance,
    double Equity,
    double DailyLossPercent,
    double DrawdownPercent,
    int OpenPositions,
    int ConsecutiveLosses,
    bool EmergencyHalt);

public sealed record RiskDecision(
    bool Allowed,
    string Code,
    string Reason,
    double RewardRisk,
    double RiskAmount)
{
    public static RiskDecision Block(string code, string reason, double rr = 0) =>
        new(false, code, reason, rr, 0);

    public static RiskDecision Allow(double rr, double riskAmount) =>
        new(true, "PASS", "Risk gate passed.", rr, riskAmount);
}
