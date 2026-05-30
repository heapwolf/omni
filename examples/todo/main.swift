import Foundation
import OmniUI
import OmniData

// MARK: - 1. Data Model

final class Task: PersistentModel, ModelSchemaAdaptor {
    let persistentModelID: PersistentIdentifier
    @MainActor var modelContext: ModelContext? = nil

    var title: String
    var isCompleted: Bool
    var dayOfWeek: String

    init(title: String, isCompleted: Bool = false, dayOfWeek: String = "MONDAY") {
        let id = UUID().uuidString
        self.persistentModelID = PersistentIdentifier(id: id, entityName: Self.schemaTableName)
        self.title = title
        self.isCompleted = isCompleted
        self.dayOfWeek = dayOfWeek
    }

    // MARK: ModelSchemaAdaptor Conformance

    static var schemaTableName: String { "Task" }

    static var schemaCreateSQL: String {
        "CREATE TABLE IF NOT EXISTS Task (id TEXT PRIMARY KEY, title TEXT, isCompleted INTEGER, dayOfWeek TEXT);"
    }

    var schemaColumns: [String] { ["title", "isCompleted", "dayOfWeek"] }

    var schemaValues: [String] {
        [title, isCompleted ? "1" : "0", dayOfWeek]
    }

    init(schemaRow: [String: String]) {
        let id = schemaRow["id"] ?? UUID().uuidString
        self.persistentModelID = PersistentIdentifier(id: id, entityName: Self.schemaTableName)
        self.title = schemaRow["title"] ?? ""
        self.isCompleted = (schemaRow["isCompleted"] == "1")
        self.dayOfWeek = schemaRow["dayOfWeek"] ?? "MONDAY"
    }

    // MARK: Hashable & Identifiable

    var id: String { persistentModelID.id }
    func hash(into hasher: inout Hasher) { hasher.combine(persistentModelID) }
    static func == (lhs: Task, rhs: Task) -> Bool { lhs.persistentModelID == rhs.persistentModelID }
}

// MARK: - 2. Presentation / UI

struct DayAccordionApp: App {
    var window = WindowConfig(
        title: "To-Do",
        width: 400,
        height: 850,
        titleBar: TitleBarConfig(isHidden: true) // Clean, borderless brutalist look
    )

    init() {}

    var body: some View {
        DayView()
            .modelContainer(for: [Task.self], inMemory: false)
    }
}

struct DayView: View {
    @Environment(\.modelContext) var context

    // Fetch only Monday's tasks, sorted by insertion order
    @Query(
        filter: Predicate(sql: "dayOfWeek = 'MONDAY'"),
        sort: [SortDescriptor(key: "id", order: .forward)]
    )
    var mondayTasks: [Task]

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Active Day Area (MONDAY)
            VStack(alignment: .leading, spacing: 8) {
                // Time & Status Bar placeholder (Top area)
                Spacer().frame(height: 40)

                Text("MONDAY")
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundColor(.black)

                Text("April, 14 2025 - 9:41am - 64°")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.gray)

                Spacer().frame(height: 20)

                // Task List
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(mondayTasks) { task in
                        TaskRow(task: task)
                    }

                    // Add Task Button (Subtle, to maintain the aesthetic)
                    Button(action: addSampleTask) {
                        Text("+ Add Task")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 10)
                }

                Spacer() // Pushes the collapsed days to the bottom
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white) // Using standard solid white/off-white for active day

            // MARK: Collapsed Accordion Days
            // Using layered opacity to create the stepped grey effect from the design
            CollapsedDayRow(title: "TUESDAY", bgOpacity: 0.1)
            CollapsedDayRow(title: "WEDNESDAY", bgOpacity: 0.15)
            CollapsedDayRow(title: "THURSDAY", bgOpacity: 0.2)
            CollapsedDayRow(title: "FRIDAY", bgOpacity: 0.25)
        }
        // Bootstrapping some initial data if the DB is empty
        // In a full SwiftUI app this would be .onAppear, but OmniUI handles commands organically
        .background(Color.white)
    }

    func addSampleTask() {
        guard let ctx = context else { return }
        let newTask = Task(title: "New task", isCompleted: false, dayOfWeek: "MONDAY")
        ctx.insert(newTask)
        try? ctx.save()
    }
}

// MARK: - 3. Custom UI Components

struct TaskRow: View {
    let task: Task
    @Environment(\.modelContext) var context

    var body: some View {
        HStack(spacing: 12) {
            // Custom Checkbox mapping to the design
            Button(action: toggleCompletion) {
                ZStack {
                    // Outer border or filled orange background
                    Rectangle()
                        .frame(width: 20, height: 20)
                        .foregroundColor(task.isCompleted ? .orange : .gray)

                    // Inner knockout for uncompleted state
                    if !task.isCompleted {
                        Rectangle()
                            .frame(width: 18, height: 18)
                            .foregroundColor(.white)
                    } else {
                        // Checkmark for completed state
                        Text("✓")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }

            // Text with dynamic strikethrough layout
            ZStack(alignment: .leading) {
                Text(task.title)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(task.isCompleted ? .gray : .black)

                // Manual strikethrough mapping using a Rectangle overlay
                if task.isCompleted {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.gray)
                }
            }

            Spacer()
        }
    }

    func toggleCompletion() {
        guard let ctx = context else { return }
        task.isCompleted.toggle()
        ctx.insert(task) // INSERT OR REPLACE safely updates the row in our SQLite implementation
        try? ctx.save()
    }
}

struct CollapsedDayRow: View {
    let title: String
    let bgOpacity: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The stepped background gradient effect
            Rectangle()
                .foregroundColor(Color.black.opacity(bgOpacity))

            Text(title)
                .font(.system(size: 36, weight: .heavy))
                .foregroundColor(.black)
                .padding(.top, 24)
                .padding(.leading, 30)
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
    }
}
