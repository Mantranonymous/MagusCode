using MagusBot.Core.Models;
using MagusBot.Core.Strategies;
using MagusBot.Network;
using MagusBot.Network.Stub;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace MagusBot.Cli;

/// <summary>
/// Point d'entrée CLI pour tester l'engine de décision en local sans réseau réel.
/// Connecte un <see cref="StubGameClient"/> au <see cref="DecisionEngine"/>,
/// itère un nombre limité d'actions et logue tout.
///
/// Usage typique : valider qu'une nouvelle stratégie ne casse rien, et vérifier
/// que la boucle réagit aux résultats du serveur (snapshot mis à jour → nouvelle décision).
/// </summary>
public static class Program
{
    public static async Task<int> Main(string[] args)
    {
        using var services = BuildServices();
        var logger = services.GetRequiredService<ILoggerFactory>().CreateLogger("MagusBot.Cli");
        logger.LogInformation("MagusBot CLI starting (stub mode, no real network).");

        var cts = new CancellationTokenSource();
        Console.CancelKeyPress += (_, e) =>
        {
            e.Cancel = true;
            logger.LogWarning("Cancel requested by user.");
            cts.Cancel();
        };

        try
        {
            await RunSessionAsync(services, logger, cts.Token);
            return 0;
        }
        catch (OperationCanceledException)
        {
            logger.LogInformation("Session cancelled.");
            return 0;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unhandled exception.");
            return 1;
        }
    }

    private static async Task RunSessionAsync(
        ServiceProvider services,
        ILogger logger,
        CancellationToken ct)
    {
        var clientLogger = services.GetRequiredService<ILogger<StubGameClient>>();
        await using var client = new StubGameClient(clientLogger, seed: 42);

        var engine = new DecisionEngine();
        var spec = BuildDemoSpec();
        var preset = BuildDemoPreset(spec);

        client.ResultReceived += (_, args) =>
            logger.LogInformation(
                "FM result: {Result} on stat #{Cid} (Δstat={Delta}, Δreliquat={ReliquatDelta:F1})",
                args.Result, args.TargetStat.CharacteristicId, args.Delta, args.ReliquatDelta);

        await client.ConnectAsync(ct);

        const int maxActions = 30;
        for (var i = 0; i < maxActions && !ct.IsCancellationRequested; i++)
        {
            var snapshot = await client.GetSnapshotAsync(ct);
            var decision = engine.Decide(snapshot, preset, spec);

            logger.LogInformation("");
            logger.LogInformation("--- Tick {Tick} ---", i + 1);
            logger.LogInformation("Reliquat: {Reliquat}", snapshot.Reliquat?.Formatted ?? "(?)");
            LogItemState(logger, snapshot.Item);
            logger.LogInformation("Decision: {Kind} — {Explanation}",
                decision.GetType().Name, FirstLine(decision.Explanation));

            switch (decision)
            {
                case Decision.ApplyRune apply:
                    await client.SendApplyRuneAsync(apply.Rune, apply.On, ct);
                    break;
                case Decision.Finished:
                    logger.LogInformation("Decision Finished — stopping session.");
                    return;
                case Decision.Blocked blocked:
                    logger.LogWarning("Blocked: {Reason}", blocked.Reason.Description);
                    return;
                case Decision.WaitingForUser waiting:
                    logger.LogWarning("Waiting for user: {Reason}", waiting.Reason);
                    return;
                default:
                    logger.LogInformation("Decision: {Kind} (no-op).", decision.GetType().Name);
                    break;
            }

            // Petit délai entre 2 ticks pour ne pas saturer la console.
            try
            {
                await Task.Delay(150, ct);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }

        logger.LogInformation("Loop reached max actions or was cancelled.");
    }

    private static void LogItemState(ILogger logger, Item? item)
    {
        if (item is null)
        {
            logger.LogInformation("Item: (none)");
            return;
        }
        logger.LogInformation("Item: {Name}", item.Name);
        foreach (var s in item.Stats)
        {
            var range = (s.MinValue, s.MaxValue) is ({ } mn, { } mx) ? $" [{mn}-{mx}]" : "";
            logger.LogInformation("  #{Cid} = {Value}{Range}", s.Kind.CharacteristicId, s.Value, range);
        }
    }

    private static string FirstLine(string s)
    {
        var idx = s.IndexOf('\n');
        return idx < 0 ? s : s[..idx];
    }

    private static ItemSpec BuildDemoSpec()
    {
        // Spec correspondant au stub d'Item dans StubGameClient.
        var stats = new List<StatSpec>
        {
            new(StatKind.Vitalite,    "Vitalité",       1,  80, 0),
            new(StatKind.Force,       "Force",          1,  20, 1),
            new(StatKind.Sagesse,     "Sagesse",        1,  10, 2),
            new(StatKind.Chance,      "Chance",         1,  15, 3),
            new(StatKind.Critique,    "% Critique",     0,   3, 4),
        };
        return ItemSpec.Create(1234, "Amulette du Bouftou (stub)", 100, stats: stats);
    }

    private static PresetBundle BuildDemoPreset(ItemSpec spec)
    {
        var stats = StatsPreset.PerfectJet(spec);
        var config = ConfigPreset.BundledFast;
        return PresetBundle.Create(stats, config);
    }

    private static ServiceProvider BuildServices() =>
        new ServiceCollection()
            .AddLogging(builder => builder
                .AddSimpleConsole(o =>
                {
                    o.SingleLine = true;
                    o.TimestampFormat = "HH:mm:ss ";
                })
                .SetMinimumLevel(LogLevel.Debug))
            .BuildServiceProvider();
}
