using System;

namespace Miningcore.Stratum
{
    public class WorkerConnectionInfo
    {
        public string PoolId { get; init; } = default!;
        public string ConnectionId { get; init; } = default!;
        public string Miner { get; set; } = default!;
        public string Worker { get; set; } = default!;
        public int Port { get; init; }

        /// <summary>
        /// Letzte Aktivität (z.B. letzter Share oder Ping).
        /// </summary>
        public DateTime LastActivity { get; set; } = DateTime.UtcNow;
    }

    public class PortStats
    {
        public int Port { get; init; }

        /// <summary>
        /// Number of active TCP stratum connections on this port.
        /// </summary>
        public int Connections { get; init; }

        /// <summary>
        /// Backward-compatible alias for Connections.
        /// </summary>
        public int ActiveWorkers { get; init; }

        public int UniqueMiners { get; init; }
        public int UniqueWorkers { get; init; }
    }
}
