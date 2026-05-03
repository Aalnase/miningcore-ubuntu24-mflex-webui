using System.Text.Json.Serialization;

namespace Miningcore.Api.Responses;

public class MinerPerformanceStats
{
    public string Miner { get; set; }
    public double Hashrate { get; set; }
    public double SharesPerSecond { get; set; }
}

public class WorkerPerformanceStats
{
    public double Hashrate { get; set; }
    public double SharesPerSecond { get; set; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public WorkerLiveStats Live { get; set; }
}

public class WorkerPerformanceStatsContainer
{
    public DateTime Created { get; set; }
    public Dictionary<string, WorkerPerformanceStats> Workers { get; set; }
}

public class MinerStats
{
    public double PendingShares { get; set; }
    public decimal PendingBalance { get; set; }
    public decimal TotalPaid { get; set; }
    public decimal TodayPaid { get; set; }
    public double MinerEffort { get; set; }
    public DateTime? LastPayment { get; set; }
    public string LastPaymentLink { get; set; }
    public WorkerPerformanceStatsContainer Performance { get; set; }
    public WorkerPerformanceStatsContainer[] PerformanceSamples { get; set; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public MinerLiveStats LiveStats { get; set; }

    public long TotalConfirmedBlocks { get; set; }
    public long TotalPendingBlocks { get; set; }
}
