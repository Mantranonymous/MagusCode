import Foundation

/// Structures correspondant à l'API api.dofusdb.fr (3.x).
/// On ne décode que les champs utiles pour Magus.

// MARK: - Wrapper de pagination

public struct DofusDBPaginated<T: Decodable & Sendable>: Decodable, Sendable {
    public let total: Int
    public let limit: Int
    public let skip: Int
    public let data: [T]
}

// MARK: - Localized string

public struct DofusDBLocalizedString: Decodable, Sendable {
    public let fr: String?
    public let en: String?
}

// MARK: - Characteristic

public struct DofusDBCharacteristic: Decodable, Sendable {
    public let id: Int
    public let keyword: String?
    public let name: DofusDBLocalizedString
    public let categoryId: Int?
    public let visible: Bool?
}

// MARK: - Item type

public struct DofusDBItemType: Decodable, Sendable {
    public let id: Int
    public let superTypeId: Int?
    public let name: DofusDBLocalizedString
}

// MARK: - Effect

public struct DofusDBEffect: Decodable, Sendable {
    public let id: Int
    public let characteristic: Int?
    public let description: DofusDBLocalizedString
    public let isInPercent: Bool?
    public let boost: Bool?
}

// MARK: - Item + possibleEffects

public struct DofusDBItem: Decodable, Sendable {
    public let id: Int
    public let typeId: Int?
    public let level: Int?
    public let name: DofusDBLocalizedString
    public let iconId: Int?
    public let itemSetId: Int?
    public let possibleEffects: [DofusDBItemEffect]?
}

public struct DofusDBItemEffect: Decodable, Sendable {
    public let effectId: Int
    public let baseEffectId: Int?
    public let order: Int?
    public let diceNum: Double?
    public let diceSide: Double?
}
