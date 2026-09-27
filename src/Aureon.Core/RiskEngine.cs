namespace Aureon.Core;

public sealed class RiskEngine
{
    public RiskDecision Evaluate(
        TradeIntent intent,
        RiskPolicy policy,
        MarketRiskState state)
    {
        if (!AreFinite(intent.Entry, intent.StopLoss, intent.TakeProfit) ||
            intent.Entry <= 0 || intent.StopLoss <= 0 || intent.TakeProfit <= 0)
            return RiskDecision.Block("INVALID_PRICE", "Entry, stop and target must be finite positive prices.");

        if (state.EmergencyHalt)
            return RiskDecision.Block("EMERGENCY_HALT", "Emergency halt is active.");

        if (!double.IsFinite(state.Balance) || !double.IsFinite(state.Equity) ||
            state.Balance <= 0 || state.Equity <= 0)
            return RiskDecision.Block("INVALID_ACCOUNT", "Balance and equity must be finite positive values.");

        if (!double.IsFinite(policy.RiskPercent) ||
            policy.RiskPercent <= 0 || policy.RiskPercent > 2.0)
            return RiskDecision.Block("INVALID_RISK", "Risk percent must be above 0 and no greater than 2%.");

        if (!double.IsFinite(policy.MinimumRewardRisk) || policy.MinimumRewardRisk <= 0)
            return RiskDecision.Block("INVALID_MIN_RR", "Minimum reward-to-risk must be positive.");

        if (state.DailyLossPercent >= policy.DailyLossLimitPercent)
            return RiskDecision.Block("DAILY_LOSS_LIMIT", "Daily loss limit reached.");

        if (state.DrawdownPercent >= policy.MaxDrawdownPercent)
            return RiskDecision.Block("DRAWDOWN_LIMIT", "Maximum drawdown limit reached.");

        if (state.OpenPositions >= policy.MaxOpenPositions)
            return RiskDecision.Block("POSITION_LIMIT", "Maximum simultaneous position limit reached.");

        if (state.ConsecutiveLosses >= policy.MaxConsecutiveLosses)
            return RiskDecision.Block("LOSS_STREAK_LIMIT", "Consecutive loss limit reached.");

        if (!HasValidGeometry(intent))
            return RiskDecision.Block("INVALID_GEOMETRY", "Stop and target are not on the correct side of entry.");

        var riskDistance = Math.Abs(intent.Entry - intent.StopLoss);
        var rewardDistance = Math.Abs(intent.TakeProfit - intent.Entry);

        if (riskDistance <= 0)
            return RiskDecision.Block("ZERO_STOP_DISTANCE", "Stop distance must be greater than zero.");

        var rr = rewardDistance / riskDistance;
        if (!double.IsFinite(rr) || rr < policy.MinimumRewardRisk)
            return RiskDecision.Block("RR_TOO_LOW", "Reward-to-risk is below the configured minimum.", rr);

        return RiskDecision.Allow(rr, CalculateRiskAmount(state.Balance, policy.RiskPercent));
    }

    public static double CalculateRiskAmount(double balance, double riskPercent)
    {
        if (!double.IsFinite(balance) || !double.IsFinite(riskPercent) ||
            balance <= 0 || riskPercent <= 0)
            return 0;

        return balance * (riskPercent / 100.0);
    }

    private static bool HasValidGeometry(TradeIntent intent) =>
        intent.Side switch
        {
            TradeSide.Buy => intent.StopLoss < intent.Entry && intent.TakeProfit > intent.Entry,
            TradeSide.Sell => intent.StopLoss > intent.Entry && intent.TakeProfit < intent.Entry,
            _ => false
        };

    private static bool AreFinite(params double[] values) => values.All(double.IsFinite);
}
