import Foundation

/// Les 6 métiers de forgemagie Dofus 3.
/// Chaque type d'équipement est lié à un seul métier.
public enum Metier: String, Codable, CaseIterable, Sendable {
    case joaillomage    // amulettes, anneaux
    case costumage      // capes, coiffes, sacs
    case cordomage      // bottes, ceintures
    case forgemage      // dague, épée, hache, faux, marteau
    case sculptemage    // arc, baguette, bâton
    case faconage       // boucliers (Façomage)

    public var displayName: String {
        switch self {
        case .joaillomage: return "Joaillomage"
        case .costumage: return "Costumage"
        case .cordomage: return "Cordomage"
        case .forgemage: return "Forgemage"
        case .sculptemage: return "Sculptemage"
        case .faconage: return "Façomage"
        }
    }

    /// Mapping DofusDB itemType.id → métier FM.
    /// IDs validés via probe API (cf. /item-types) :
    /// Amulette=1, Arc=2, Baguette=3, Bâton=4, Dague=5, Épée=6, Marteau=7, Pelle=8,
    /// Anneau=9, Ceinture=10, Bottes=11.
    /// Les types manquants (cape, coiffe, sac, bouclier, hache, faux) seront ajoutés
    /// après inventaire complet de la table item_types.
    public static func from(itemTypeId: Int) -> Metier? {
        switch itemTypeId {
        case 1, 9:                   return .joaillomage      // amulette, anneau
        case 2, 3, 4:                return .sculptemage      // arc, baguette, bâton
        case 5, 6, 7, 8:             return .forgemage        // dague, épée, marteau, pelle
        case 10, 11:                 return .cordomage        // ceinture, bottes
        // À compléter : capes / coiffes / sacs (costumage), bouclier (faconage),
        // hache / faux (forgemage)
        default: return nil
        }
    }
}
