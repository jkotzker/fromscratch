import FromScratchCore
import Observation
import SwiftUI

/// What the Settings window shows, kept in step with the app model: a change made from the menu,
/// a shortcut or the font panel arrives through `AppModel.didChange`, and a change made here goes
/// through the same controllers the menu uses.
@MainActor
@Observable
final class SettingsModel {
    struct SchemeOption: Identifiable, Hashable {
        let id: String
        let name: String
    }

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let schemeController: SchemeController
    @ObservationIgnored private let fontController: FontController

    private(set) var schemes: [SchemeOption] = []
    private(set) var fontDescription = ""
    private var activeSchemeID = ""
    private var highlightsCurrentLine = true

    init(app: AppModel, schemes: SchemeController, fonts: FontController) {
        self.app = app
        schemeController = schemes
        fontController = fonts
        refresh()
        app.didChange.append { [weak self] in self?.refresh() }
    }

    /// The scheme on screen (the resolved one, as the menu's checkmark), stored when changed.
    var selectedSchemeId: String {
        get { activeSchemeID }
        set { schemeController.select(id: newValue) }
    }

    var highlightCurrentLine: Bool {
        get { highlightsCurrentLine }
        set { app.setHighlightCurrentLine(newValue) }
    }

    func chooseFont() {
        fontController.showFontPanel()
    }

    /// Assigns only what changed, so an unrelated change does not redraw the form.
    private func refresh() {
        let options = app.schemes.all.map { SchemeOption(id: $0.id, name: $0.name) }
        if options != schemes { schemes = options }
        if app.scheme.id != activeSchemeID { activeSchemeID = app.scheme.id }
        let font = fontController.displayDescription
        if font != fontDescription { fontDescription = font }
        if app.settings.highlightCurrentLine != highlightsCurrentLine {
            highlightsCurrentLine = app.settings.highlightCurrentLine
        }
    }
}

/// Settings: three choices that apply as soon as they are made, so there is no OK button.
struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Picker("Colour scheme:", selection: $model.selectedSchemeId) {
                ForEach(model.schemes) { scheme in
                    Text(scheme.name).tag(scheme.id)
                }
            }
            LabeledContent("Font:") {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.fontDescription)
                        .textSelection(.enabled)
                    Button("Choose…") { model.chooseFont() }
                        .help("Opens the font panel set to the current font")
                }
            }
            Toggle("Highlight current line", isOn: $model.highlightCurrentLine)
        }
        .formStyle(.columns)
        .padding(20)
        .frame(minWidth: 380)
        .fixedSize()
    }
}
