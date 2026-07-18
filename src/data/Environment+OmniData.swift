// src/data/Environment+OmniData.swift
import OmniUI

public extension EnvironmentValues {
    /// SwiftData spells the context `\.modelContext`. It reads the object
    /// `.modelContainer(...)` already cascades, so the keypath and
    /// @EnvironmentObject<ModelContext> name one object, not two copies.
    var modelContext: ModelContext? { object(ModelContext.self) }
}
