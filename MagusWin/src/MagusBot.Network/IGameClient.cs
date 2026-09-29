using MagusBot.Core.Models;

namespace MagusBot.Network;

/// <summary>
/// Contrat haut-niveau pour un client réseau Dofus 3. L'implémentation réelle
/// nécessite le RE du protocole (voir <c>docs/REVERSE_ENGINEERING.md</c>).
///
/// L'orchestrateur (CLI ou UI) parle uniquement à cette interface :
/// <list type="bullet">
/// <item><see cref="GetSnapshotAsync"/> renvoie l'état courant de l'établi FM</item>
/// <item><see cref="SendApplyRuneAsync"/> demande au jeu de poser une rune</item>
/// <item><see cref="ResultReceived"/> notifie SC/SN/EC + delta de stats</item>
/// </list>
///
/// Une fois le protocole reverse-engineerd, swap <see cref="Stub.StubGameClient"/>
/// par une implémentation réelle (<c>DofusGameClient</c>) sans toucher le reste.
/// </summary>
public interface IGameClient : IAsyncDisposable
{
    /// <summary>Vrai si le client est connecté au serveur Dofus.</summary>
    bool IsConnected { get; }

    /// <summary>
    /// Connecte au serveur. Pour le stub, no-op instantanée. Pour la vraie impl,
    /// fait login + handshake + sélection de personnage.
    /// </summary>
    Task ConnectAsync(CancellationToken ct = default);

    /// <summary>Récupère l'état actuel de la session FM (item + reliquat + historique).</summary>
    Task<GameStateSnapshot> GetSnapshotAsync(CancellationToken ct = default);

    /// <summary>
    /// Demande au jeu de poser une rune sur l'item courant. Le résultat arrive
    /// de façon asynchrone via <see cref="ResultReceived"/>.
    /// </summary>
    Task SendApplyRuneAsync(Rune rune, StatKind on, CancellationToken ct = default);

    /// <summary>Événement déclenché quand le serveur renvoie le résultat d'une pose.</summary>
    event EventHandler<FmResultEventArgs>? ResultReceived;

    /// <summary>Événement déclenché quand l'état de session change (item changé, reliquat MAJ).</summary>
    event EventHandler<StateChangedEventArgs>? StateChanged;
}

/// <summary>Arguments transmis par <see cref="IGameClient.ResultReceived"/>.</summary>
public sealed class FmResultEventArgs : EventArgs
{
    public required CombineResult Result { get; init; }
    public required Rune Rune { get; init; }
    public required StatKind TargetStat { get; init; }
    /// <summary>Δstat appliquée (positif = gain, négatif = perte).</summary>
    public int Delta { get; init; }
    /// <summary>Δreliquat appliqué.</summary>
    public double ReliquatDelta { get; init; }
    /// <summary>Snapshot après application du résultat (optionnel).</summary>
    public GameStateSnapshot? Snapshot { get; init; }
}

/// <summary>Arguments transmis par <see cref="IGameClient.StateChanged"/>.</summary>
public sealed class StateChangedEventArgs : EventArgs
{
    public required GameStateSnapshot Snapshot { get; init; }
}
