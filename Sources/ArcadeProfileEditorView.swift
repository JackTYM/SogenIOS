import SwiftUI

/// Full-screen editor for building/editing one ArcadeProfile. Not shown over the live running
/// guest -- editing and playing are deliberately separate screens.
struct ArcadeProfileEditorView: View {
    @State var profile: ArcadeProfile
    let onSave: (ArcadeProfile) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var showingAddMenu = false
    @State private var editingButtonID: UUID?
    @State private var editingJoystick = false
    @State private var joystickDragStart: CGPoint?

    private let canvasAspectRatio: CGFloat = 320.0 / 180.0

    var body: some View {
        VStack(spacing: 12) {
            TextField("Profile Name", text: $profile.name)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            GeometryReader { geometry in
                ZStack(alignment: .topTrailing) {
                    Color(white: 0.1)

                    ForEach(profile.buttons) { button in
                        if let index = profile.buttons.firstIndex(where: { $0.id == button.id }) {
                            EditableButtonView(
                                button: $profile.buttons[index],
                                canvasSize: geometry.size,
                                onTap: { editingButtonID = button.id })
                        }
                    }

                    if let joystick = profile.joystick {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.6), lineWidth: 2)
                            .frame(width: joystick.radius * geometry.size.width * 2,
                                   height: joystick.radius * geometry.size.width * 2)
                            .position(x: joystick.position.x * geometry.size.width,
                                      y: joystick.position.y * geometry.size.height)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let start = joystickDragStart ?? joystick.position
                                        if joystickDragStart == nil { joystickDragStart = joystick.position }
                                        profile.joystick?.position = CGPoint(
                                            x: start.x + value.translation.width / geometry.size.width,
                                            y: start.y + value.translation.height / geometry.size.height)
                                    }
                                    .onEnded { _ in joystickDragStart = nil }
                            )
                            .onTapGesture { editingJoystick = true }
                    }

                    Button(action: { showingAddMenu = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .padding(8)
                    .confirmationDialog("Add Control", isPresented: $showingAddMenu) {
                        Button("Add Button") { addButton() }
                        if profile.joystick == nil {
                            Button("Add Joystick") { addJoystick() }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .aspectRatio(canvasAspectRatio, contentMode: .fit)
            .padding(.horizontal)

            Button("Save") {
                onSave(profile)
                dismiss()
            }
            .padding()
        }
        .sheet(isPresented: Binding(
            get: { editingButtonID != nil },
            set: { if !$0 { editingButtonID = nil } }
        )) {
            if let id = editingButtonID, let index = profile.buttons.firstIndex(where: { $0.id == id }) {
                ButtonConfigSheet(button: $profile.buttons[index]) {
                    profile.buttons.remove(at: index)
                    editingButtonID = nil
                }
            }
        }
        .sheet(isPresented: $editingJoystick) {
            if profile.joystick != nil {
                JoystickConfigSheet(joystick: Binding(
                    get: { profile.joystick! },
                    set: { profile.joystick = $0 }
                )) {
                    profile.joystick = nil
                    editingJoystick = false
                }
            }
        }
    }

    private func addButton() {
        let button = ArcadeButton(
            id: UUID(), label: "New", position: CGPoint(x: 0.5, y: 0.5),
            size: CGSize(width: 0.12, height: 0.12),
            action: arcadeKeyCatalog[0].action)
        profile.buttons.append(button)
    }

    private func addJoystick() {
        profile.joystick = ArcadeJoystick(
            position: CGPoint(x: 0.5, y: 0.5), radius: 0.1,
            up: nil, down: nil, left: nil, right: nil)
    }
}

private struct EditableButtonView: View {
    @Binding var button: ArcadeButton
    let canvasSize: CGSize
    let onTap: () -> Void

    @State private var dragStartPosition: CGPoint?

    var body: some View {
        Text(button.label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: button.size.width * canvasSize.width,
                   height: button.size.height * canvasSize.height)
            .background(Color.blue.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .position(x: button.position.x * canvasSize.width,
                      y: button.position.y * canvasSize.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let start = dragStartPosition ?? button.position
                        if dragStartPosition == nil {
                            dragStartPosition = button.position
                        }
                        button.position = CGPoint(
                            x: start.x + value.translation.width / canvasSize.width,
                            y: start.y + value.translation.height / canvasSize.height)
                    }
                    .onEnded { _ in
                        dragStartPosition = nil
                    }
            )
            .onTapGesture(perform: onTap)
    }
}

private struct ButtonConfigSheet: View {
    @Binding var button: ArcadeButton
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedKeyID: String?
    @State private var isMouseClick = false
    @State private var mouseButton: MouseButton = .left

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("Label", text: $button.label)
                }
                Section("Binding") {
                    Toggle("Mouse click instead of key", isOn: $isMouseClick)
                    if isMouseClick {
                        Picker("Button", selection: $mouseButton) {
                            Text("Left").tag(MouseButton.left)
                            Text("Right").tag(MouseButton.right)
                        }
                    } else {
                        Picker("Key", selection: $selectedKeyID) {
                            ForEach(arcadeKeyCatalog) { key in
                                Text(key.name).tag(Optional(key.id))
                            }
                        }
                    }
                }
                Section {
                    Button("Delete Control", role: .destructive, action: onDelete)
                }
            }
            .navigationTitle("Edit Button")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyBinding()
                        dismiss()
                    }
                }
            }
            .onAppear { loadCurrentBinding() }
        }
    }

    private func loadCurrentBinding() {
        switch button.action {
        case .key(let vk, let scanCode, let extended):
            isMouseClick = false
            selectedKeyID = arcadeKeyCatalog.first {
                $0.vk == vk && $0.scanCode == scanCode && $0.extended == extended
            }?.id
        case .mouseClick(let side):
            isMouseClick = true
            mouseButton = side
        }
    }

    private func applyBinding() {
        if isMouseClick {
            button.action = .mouseClick(button: mouseButton)
        } else if let id = selectedKeyID, let key = arcadeKeyCatalog.first(where: { $0.id == id }) {
            button.action = key.action
        }
    }
}

private struct JoystickConfigSheet: View {
    @Binding var joystick: ArcadeJoystick
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var upID: String?
    @State private var downID: String?
    @State private var leftID: String?
    @State private var rightID: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Directions") {
                    directionPicker("Up", selection: $upID)
                    directionPicker("Down", selection: $downID)
                    directionPicker("Left", selection: $leftID)
                    directionPicker("Right", selection: $rightID)
                }
                Section {
                    Button("Delete Joystick", role: .destructive, action: onDelete)
                }
            }
            .navigationTitle("Edit Joystick")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyBindings()
                        dismiss()
                    }
                }
            }
            .onAppear { loadCurrentBindings() }
        }
    }

    private func directionPicker(_ label: String, selection: Binding<String?>) -> some View {
        Picker(label, selection: selection) {
            Text("None").tag(String?.none)
            ForEach(arcadeKeyCatalog) { key in
                Text(key.name).tag(Optional(key.id))
            }
        }
    }

    private func keyID(for action: ArcadeActionKind?) -> String? {
        guard case .key(let vk, let scanCode, let extended) = action else { return nil }
        return arcadeKeyCatalog.first {
            $0.vk == vk && $0.scanCode == scanCode && $0.extended == extended
        }?.id
    }

    private func loadCurrentBindings() {
        upID = keyID(for: joystick.up)
        downID = keyID(for: joystick.down)
        leftID = keyID(for: joystick.left)
        rightID = keyID(for: joystick.right)
    }

    private func applyBindings() {
        joystick.up = upID.flatMap { id in arcadeKeyCatalog.first { $0.id == id }?.action }
        joystick.down = downID.flatMap { id in arcadeKeyCatalog.first { $0.id == id }?.action }
        joystick.left = leftID.flatMap { id in arcadeKeyCatalog.first { $0.id == id }?.action }
        joystick.right = rightID.flatMap { id in arcadeKeyCatalog.first { $0.id == id }?.action }
    }
}
