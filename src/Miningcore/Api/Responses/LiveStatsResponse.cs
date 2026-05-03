using System.Text.Json.Serialization;

namespace Miningcore.Api.Responses;

public class LiveConnectionInfo
{
    public string Miner { get; set; }
    public string Worker { get; set; }
    public int Port { get; set; }
    public DateTime LastActivity { get; set; }
}

public class LivePortStats
{
    public int Port { get; set; }
    public int Connections { get; set; }
    public int UniqueMiners { get; set; }
    public int UniqueWorkers { get; set; }
}

public class WorkerLiveStats
{
    public bool Online { get; set; }
    public int Connections { get; set; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int[] Ports { get; set; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public DateTime? LastActivity { get; set; }
}

public class PoolLiveStats
{
    public int OnlineMiners { get; set; }
    public int OnlineWorkers { get; set; }
    public int OnlineConnections { get; set; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public LivePortStats[] Ports { get; set; }
}

public class MinerLiveStats
{
    public int OnlineWorkers { get; set; }
    public int OnlineConnections { get; set; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public Dictionary<string, WorkerLiveStats> Workers { get; set; }
}

public class PoolConnectionsResponse
{
    public PoolLiveStats Summary { get; set; }
    public LiveConnectionInfo[] Connections { get; set; }
}
