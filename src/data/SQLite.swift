// MARK: - OmniData.swift
// Consolidates Schema, Querying, Engine, and UI Bindings

import Foundation
import CSQLite
import OmniUI // Integrates strictly via public APIs

// MARK: - Schema & Identifiers

public struct PersistentIdentifier: Codable, Hashable, Equatable, Sendable {
    public let id: String
    public let entityName: String

    public init(id: String, entityName: String) {
        self.id = id
        self.entityName = entityName
    }
}

/// Note: Removed Apple's 'Observable' to support macOS 13 / iOS 15.
/// OmniUI's reactivity is handled at the ModelContext level instead.
public protocol PersistentModel: Identifiable, Hashable {
    @MainActor var modelContext: ModelContext? { get }
    var persistentModelID: PersistentIdentifier { get }
}

public protocol ModelSchemaAdaptor {
    static var schemaTableName: String { get }
    static var schemaCreateSQL: String { get }
    var schemaColumns: [String] { get }
    var schemaValues: [String] { get }
    init(schemaRow: [String: String])
}

// MARK: - Querying & Predicates

public struct Predicate<T> {
    public let sqlWhereClause: String
    public init(sql: String) {
        self.sqlWhereClause = sql
    }
}

public struct SortDescriptor<T> {
    public let key: String
    public let order: SortOrder
    public enum SortOrder { case forward, reverse }

    public init(key: String, order: SortOrder = .forward) {
        self.key = key
        self.order = order
    }
}

public struct FetchDescriptor<T: PersistentModel> {
    public var predicate: Predicate<T>?
    public var sortBy: [SortDescriptor<T>]
    public var fetchLimit: Int?
    public var fetchOffset: Int?
    public var includePendingChanges: Bool

    public init(predicate: Predicate<T>? = nil, sortBy: [SortDescriptor<T>] = [], includePendingChanges: Bool = true) {
        self.predicate = predicate
        self.sortBy = sortBy
        self.includePendingChanges = includePendingChanges
    }
}

// MARK: - The Storage Engine

internal final class SQLiteEngine {
    private var dbPointer: OpaquePointer?

    init(configuration: ModelConfiguration) throws {
        let path = configuration.isStoredInMemoryOnly ? ":memory:" : configuration.url.path

        if sqlite3_open(path, &dbPointer) != SQLITE_OK {
            let errorMsg = String(cString: sqlite3_errmsg(dbPointer))
            sqlite3_close(dbPointer)
            throw NSError(domain: "SQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    deinit {
        if let dbPointer { sqlite3_close(dbPointer) }
    }

    internal func execute(_ sql: String) throws {
        var errorMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(dbPointer, sql, nil, nil, &errorMsg) != SQLITE_OK {
            let message = errorMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMsg)
            throw NSError(domain: "SQLite", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    internal func query(_ sql: String, rowHandler: ([String: String]) -> Void) throws {
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(dbPointer, sql, -1, &stmt, nil) != SQLITE_OK {
            let errorMsg = String(cString: sqlite3_errmsg(dbPointer))
            throw NSError(domain: "SQLite", code: 3, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let columnCount = sqlite3_column_count(stmt)
            var row: [String: String] = [:]

            for i in 0..<columnCount {
                if let namePointer = sqlite3_column_name(stmt, i),
                   let valPointer = sqlite3_column_text(stmt, i) {

                    let columnName = String(cString: namePointer)
                    let columnValue = String(cString: valPointer)
                    row[columnName] = columnValue
                }
            }
            rowHandler(row)
        }
    }
}

// MARK: - Runtime & Context

public struct ModelConfiguration {
    public var url: URL
    public var isStoredInMemoryOnly: Bool
    public var allowsSave: Bool

    public init(isStoredInMemoryOnly: Bool = false, url: URL? = nil, allowsSave: Bool = true) {
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
        self.allowsSave = allowsSave
        if let url = url {
            self.url = url
        } else {
            // The app's own directory: Documents is the user's, and on a Mac
            // every app's.
            self.url = AppDirectories.support.appendingPathComponent("default.store")
        }
    }
}

@MainActor
public final class ModelContainer {
    public let configurations: [ModelConfiguration]
    public let mainContext: ModelContext
    internal let engine: SQLiteEngine

    public init(for modelTypes: [any PersistentModel.Type], configurations: ModelConfiguration...) throws {
        self.configurations = configurations.isEmpty ? [ModelConfiguration()] : configurations
        self.engine = try SQLiteEngine(configuration: self.configurations.first!)

        self.mainContext = ModelContext(engine: self.engine)
        self.mainContext.bind(to: self)

        for type in modelTypes {
            guard let schemaType = type as? ModelSchemaAdaptor.Type else {
                fatalError("Type \(type) does not conform to ModelSchemaAdaptor.")
            }
            try self.engine.execute(schemaType.schemaCreateSQL)
        }
    }
}

@MainActor
public final class ModelContext: OmniUI.OmniObservableObject {
    public private(set) weak var container: ModelContainer?
    private let engine: SQLiteEngine

    // OmniUI's Engine will automatically track dependencies via this @Published
    // property. On Apple this is the real Combine @Published: mutating it
    // fires objectWillChange, which OmniUI.EnvironmentObject (used below) is
    // subscribed to. On other platforms it's OmniUI's own Published, which
    // registers the dependency directly — either way, mutating it safely
    // triggers Engine.render(n) on all dependent views without needing access
    // to the internal Tracker.deps dictionary.
    #if canImport(Combine)
    @Published public private(set) var changeCounter: Int = 0
    #else
    @OmniUI.Published public private(set) var changeCounter: Int = 0
    #endif

    public var hasChanges: Bool {
        return !insertedModels.isEmpty || !deletedModels.isEmpty
    }

    private var insertedModels: [PersistentIdentifier: any PersistentModel] = [:]
    private var deletedModels: [PersistentIdentifier: any PersistentModel] = [:]

    internal init(engine: SQLiteEngine) {
        self.engine = engine
    }

    internal func bind(to container: ModelContainer) {
        self.container = container
    }

    public func insert<T: PersistentModel>(_ model: T) {
        insertedModels[model.persistentModelID] = model
    }

    public func delete<T: PersistentModel>(_ model: T) {
        deletedModels[model.persistentModelID] = model
        insertedModels.removeValue(forKey: model.persistentModelID)
    }

    public func save() throws {
        guard hasChanges else { return }

        try engine.execute("BEGIN TRANSACTION;")
        do {
            for (id, _) in deletedModels {
                let sql = "DELETE FROM \(id.entityName) WHERE id = '\(id.id)';"
                try engine.execute(sql)
            }

            for (id, model) in insertedModels {
                guard let persistable = model as? ModelSchemaAdaptor else {
                    throw NSError(domain: "OmniData", code: 101, userInfo: [NSLocalizedDescriptionKey: "Model lacks schema conformance"])
                }

                let columns = persistable.schemaColumns.joined(separator: ", ")
                let values = persistable.schemaValues.map { "'\($0)'" }.joined(separator: ", ")
                let sql = "INSERT OR REPLACE INTO \(id.entityName) (id, \(columns)) VALUES ('\(id.id)', \(values));"
                try engine.execute(sql)
            }

            try engine.execute("COMMIT;")

            insertedModels.removeAll()
            deletedModels.removeAll()

            // This triggers OmniUI's dependency tracker natively.
            changeCounter += 1

        } catch {
            try engine.execute("ROLLBACK;")
            throw error
        }
    }

    public func rollback() {
        insertedModels.removeAll()
        deletedModels.removeAll()
    }

    public func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        guard let schemaType = T.self as? ModelSchemaAdaptor.Type else { return [] }

        var sql = "SELECT * FROM \(schemaType.schemaTableName)"

        if let predicate = descriptor.predicate {
            sql += " WHERE \(predicate.sqlWhereClause)"
        }

        if !descriptor.sortBy.isEmpty {
            let sorts = descriptor.sortBy.map { "\($0.key) \($0.order == .forward ? "ASC" : "DESC")" }
            sql += " ORDER BY \(sorts.joined(separator: ", "))"
        }

        if let limit = descriptor.fetchLimit {
            sql += " LIMIT \(limit)"
            if let offset = descriptor.fetchOffset {
                sql += " OFFSET \(offset)"
            }
        }

        var results: [T] = []

        try engine.query(sql) { rowDict in
            if let instance = schemaType.init(schemaRow: rowDict) as? T {
                results.append(instance)
            }
        }

        if descriptor.includePendingChanges {
            let pending = insertedModels.values.compactMap { $0 as? T }
            results.append(contentsOf: pending)
        }

        return results
    }
}

// MARK: - Presentation (OmniUI Integration)

public extension View {
    /// Injects the ModelContext using OmniUI's native environmentObject cascade
    func modelContainer(_ container: ModelContainer) -> some View {
        self.environmentObject(container.mainContext)
    }

    @MainActor
    func modelContainer(for modelTypes: [any PersistentModel.Type], inMemory: Bool = false) -> some View {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container = try! ModelContainer(for: modelTypes, configurations: config)
        return self.environmentObject(container.mainContext)
    }
}

@propertyWrapper @MainActor
public struct Query<T: PersistentModel> {
    private let fetchDescriptor: FetchDescriptor<T>

    // We instantiate OmniUI's own EnvironmentObject wrapper here. Since this wrapper
    // is compiled within OmniUI, it safely accesses the internal Tracker.current node!
    private var contextProvider = OmniUI.EnvironmentObject<ModelContext>()

    public var wrappedValue: [T] {
        let context = contextProvider.wrappedValue

        // Reading the @Published property registers the active OmniUI view
        // to re-render whenever context.save() increments the counter.
        _ = context.changeCounter

        do {
            return try context.fetch(fetchDescriptor)
        } catch {
            Omni.log("Query fetch failed for \(T.self): \(error)")
            return []
        }
    }

    public init(
        filter: Predicate<T>? = nil,
        sort: [SortDescriptor<T>] = []
    ) {
        self.fetchDescriptor = FetchDescriptor(predicate: filter, sortBy: sort)
    }
}
