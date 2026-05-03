using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;

namespace Miningcore.Stratum
{
    public class WorkerConnectionTracker : IWorkerConnectionTracker
    {
        // Key: poolId:connectionId
        private readonly ConcurrentDictionary<string, WorkerConnectionInfo> _connections
            = new ConcurrentDictionary<string, WorkerConnectionInfo>();

        private static string BuildKey(string poolId, string connectionId)
            => $"{poolId}:{connectionId}";

        public void RegisterConnection(string poolId, string connectionId, int port)
        {
            var key = BuildKey(poolId, connectionId);

            var info = new WorkerConnectionInfo
            {
                PoolId = poolId,
                ConnectionId = connectionId,
                Port = port,
                Miner = string.Empty,
                Worker = string.Empty,
                LastActivity = DateTime.UtcNow
            };

            _connections[key] = info;
        }

        public void SetIdentity(string poolId, string connectionId, string miner, string worker)
        {
            var key = BuildKey(poolId, connectionId);

            if (_connections.TryGetValue(key, out var info))
            {
                info.Miner = miner ?? string.Empty;
                info.Worker = worker ?? string.Empty;
                info.LastActivity = DateTime.UtcNow;
            }
        }

        public void UpdateActivity(string poolId, string connectionId)
        {
            var key = BuildKey(poolId, connectionId);

            if (_connections.TryGetValue(key, out var info))
            {
                info.LastActivity = DateTime.UtcNow;
            }
        }

        public void UnregisterConnection(string poolId, string connectionId)
        {
            var key = BuildKey(poolId, connectionId);
            _connections.TryRemove(key, out _);
        }

        public IReadOnlyList<WorkerConnectionInfo> GetActiveConnections(string poolId)
        {
            var now = DateTime.UtcNow;
            // Optional: Inaktive Sessions nach X Minuten rauswerfen
            var maxIdle = TimeSpan.FromMinutes(10);

            var result = _connections.Values
                .Where(x => x.PoolId == poolId &&
                            (now - x.LastActivity) <= maxIdle)
                .ToList();

            return result;
        }

        private static string BuildWorkerKey(WorkerConnectionInfo info)
        {
            var miner = info.Miner ?? string.Empty;
            var worker = info.Worker ?? string.Empty;
            return $"{miner}:{worker}";
        }

        public IReadOnlyList<PortStats> GetPortStats(string poolId)
        {
            var workers = GetActiveConnections(poolId);

            var query =
                from w in workers
                group w by w.Port
                into g
                select new PortStats
                {
                    Port = g.Key,
                    Connections = g.Count(),
                    ActiveWorkers = g.Count(), // backward-compatible alias
                    UniqueMiners = g.Select(x => x.Miner).Where(x => !string.IsNullOrEmpty(x)).Distinct(StringComparer.OrdinalIgnoreCase).Count(),
                    UniqueWorkers = g.Where(x => !string.IsNullOrEmpty(x.Miner)).Select(BuildWorkerKey).Distinct(StringComparer.OrdinalIgnoreCase).Count()
                };

            return query.OrderBy(x => x.Port).ToList();
        }
    }
}
