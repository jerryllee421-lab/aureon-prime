using Aureon.Core;
using cAlgo.API;

namespace cAlgo.Robots;

[Robot(TimeZone = TimeZones.UTC, AccessRights = AccessRights.None)]
public sealed class AureonPrimeBot : Robot
{
    private const string Version = "0.1.0";
    private const string BotLabel = "AUREON_PRIME";

    [Parameter("Execution Armed", DefaultValue = false)]
    public bool ExecutionArmed { get; set; }

    [Parameter("Risk %", DefaultValue = 0.50)]
    public double RiskPercent { get; set; }

    [Parameter("Minimum R:R", DefaultValue = 1.80)]
    public double MinimumRewardRisk { get; set; }

    [Parameter("Daily Loss Limit %", DefaultValue = 2.00)]
    public double DailyLossLimitPercent { get; set; }

    [Parameter("Max Drawdown %", DefaultValue = 8.00)]
    public double MaxDrawdownPercent { get; set; }

    [Parameter("Max Open Positions", DefaultValue = 1)]
    public int MaxOpenPositions { get; set; }

    [Parameter("Max Consecutive Losses", DefaultValue = 2)]
    public int MaxConsecutiveLosses { get; set; }

    [Parameter("Emergency Halt", DefaultValue = false)]
    public bool EmergencyHalt { get; set; }

    private readonly RiskEngine _riskEngine = new();
    private double _sessionStartEquity;
    private double _peakEquity;
    private int _consecutiveLosses = 0;

    protected override void OnStart()
    {
        _sessionStartEquity = Account.Equity;
        _peakEquity = Account.Equity;

        Print("AUREON Ω PRIME v{0} started on {1}. ExecutionArmed={2}",
            Version, SymbolName, ExecutionArmed);
        Print("V0.1 is a safety kernel only: no strategy is authorised to create orders.");
    }

    protected override void OnBarClosed()
    {
        UpdateEquityState();

        if (!ExecutionArmed)
            return;

        // V0.1 intentionally has no strategy signal provider.
        // A later strategy module must create a TradeIntent and pass Authorize()
        // before an execution method is permitted to place any order.
    }

    protected override void OnStop()
    {
        Print("AUREON Ω PRIME v{0} stopped.", Version);
    }

    private RiskDecision Authorize(TradeIntent intent)
    {
        var policy = new RiskPolicy(
            RiskPercent,
            MinimumRewardRisk,
            DailyLossLimitPercent,
            MaxDrawdownPercent,
            MaxOpenPositions,
            MaxConsecutiveLosses);

        var equity = Account.Equity;
        var dailyLoss = PercentLoss(_sessionStartEquity, equity);
        var drawdown = PercentLoss(_peakEquity, equity);
        var openPositions = Positions.FindAll(BotLabel, SymbolName).Length;

        var state = new MarketRiskState(
            Account.Balance,
            equity,
            dailyLoss,
            drawdown,
            openPositions,
            _consecutiveLosses,
            EmergencyHalt);

        var decision = _riskEngine.Evaluate(intent, policy, state);

        Print(
            "RISK {0} | setup={1} | code={2} | rr={3:F2} | riskAmount={4:F2}",
            decision.Allowed ? "PASS" : "BLOCK",
            intent.SetupId,
            decision.Code,
            decision.RewardRisk,
            decision.RiskAmount);

        return decision;
    }

    private void UpdateEquityState()
    {
        if (Account.Equity > _peakEquity)
            _peakEquity = Account.Equity;
    }

    private static double PercentLoss(double reference, double current)
    {
        if (reference <= 0 || current >= reference)
            return 0;

        return ((reference - current) / reference) * 100.0;
    }
}
