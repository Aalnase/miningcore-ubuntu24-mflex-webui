using System.Collections.Generic;
using System.Reactive;
using System.Reactive.Linq;
using Miningcore.Mining;

namespace Miningcore.Blockchain.Zano;

public class ZanoWorkerContext : WorkerContextBase
{
    /// <summary>
    /// Usually a wallet address
    /// NOTE: May include paymentid (seperated by a dot .)
    /// </summary>
    public override string Miner { get; set; }

    /// <summary>
    /// Arbitrary worker identififer for miners using multiple rigs
    /// </summary>
    public override string Worker { get; set; }

    /// <summary>
    /// Stratum protocol version
    /// </summary>
    public int ProtocolVersion { get; set; }

    /// <summary>
    /// Current N job(s) assigned to this worker
    /// </summary>
    public Queue<ZanoWorkerJob> validJobs { get; private set; } = new();

    public virtual void AddJob(ZanoWorkerJob job, int maxActiveJobs)
    {
        if(!validJobs.Contains(job))
            validJobs.Enqueue(job);

        while(validJobs.Count > maxActiveJobs)
            validJobs.Dequeue();
    }

    public ZanoWorkerJob GetJob(string jobId)
    {
        // Important: use the newest matching job, not the oldest.
        //
        // Some ZANO / EthProxy-style miners can receive multiple jobs with the
        // same job id around block changes, VarDiff updates or duplicate job
        // pushes. Returning the oldest match makes valid current submissions
        // look like stale work and causes "block expired" rejects.
        var jobs = validJobs.ToArray();

        for(var i = jobs.Length - 1; i >= 0; i--)
        {
            if(jobs[i].Id == jobId)
                return jobs[i];
        }

        return null;
    }
}
