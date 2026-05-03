using System.Collections.Generic;

namespace Miningcore.Stratum
{
    public interface IWorkerConnectionTracker
    {
        void RegisterConnection(string poolId, string connectionId, int port);
        void SetIdentity(string poolId, string connectionId, string miner, string worker);
        void UpdateActivity(string poolId, string connectionId);
        void UnregisterConnection(string poolId, string connectionId);

        IReadOnlyList<WorkerConnectionInfo> GetActiveConnections(string poolId);
        IReadOnlyList<PortStats> GetPortStats(string poolId);
    }
}
