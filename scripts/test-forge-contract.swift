import Foundation

@main
struct ForgeContractTests {
    static func main() {
        let html = """
        <html><head><style>:root { --space-md: 12px; }</style></head>
        <body>
          <section data-screen="stats" data-route="progress">
            <div id="weekly-summary" data-forge-id="weekly-card"></div>
            <a href="#history">History</a>
          </section>
          <script>
            HTMLAppData.kv.set("settings-v1", {});
            HTMLAppData.collection("notes");
            HTMLAppNative.db.put("workouts", "w1", {});
            HTMLAppNative.notifications.schedule({});
          </script>
        </body></html>
        """
        let model = ForgeSemanticAppModel.build(html: html, purpose: "Workout tracker")
        precondition(model.screenIDs?.contains("stats") == true)
        precondition(model.routeIDs?.contains("progress") == true)
        precondition(model.routeIDs?.contains("history") == true)
        precondition(model.designTokens?.contains("--space-md") == true)
        precondition(model.storageKeys.contains("settings-v1"))
        precondition(model.databaseCollections.contains("notes"))
        precondition(model.databaseCollections.contains("workouts"))
        precondition(model.nativeMethods.contains("notifications.schedule"))

        var retained = model
        retained.recentEdits = ["Made the dashboard cards compact"]
        let change = ForgeEditContract.make(
            request: "do the same for stats",
            model: retained,
            taste: "Prefer compact layout"
        )
        precondition(change.targets.contains("stats"))
        precondition(change.implementationBrief.contains("Made the dashboard cards compact"))
        precondition(change.implementationBrief.contains("Prefer compact layout"))
        let cosmetic = ForgeEditContract.make(request: "make stats cleaner",
                                              model: model, taste: "")
        precondition(cosmetic.scope == .appearance)
        precondition(cosmetic.targets.contains("stats"))

        let afterRemovingKey = html.replacingOccurrences(
            of: #"HTMLAppData.kv.set("settings-v1", {});"#, with: "")
        let unrelated = afterRemovingKey +
            #"<script>HTMLAppData.migrate("other", 2, {});</script>"#
        let violations = ForgeEditSafetyGate.violations(
            before: html, after: unrelated, request: "make stats cleaner"
        )
        precondition(violations.contains { $0.kind == "persistent storage keys" })
        let withExplicitReference = afterRemovingKey +
            #"<script>HTMLAppData.migrate("settings", 2, {1: async () => { const prior = "settings-v1"; }});</script>"#
        precondition(ForgeEditSafetyGate.violations(
            before: html, after: withExplicitReference, request: "update storage"
        ).isEmpty)

        let withoutNative = html.replacingOccurrences(
            of: "HTMLAppNative.notifications.schedule({});", with: "")
        let bridgeViolations = ForgeEditSafetyGate.violations(
            before: html, after: withoutNative, request: "make stats cleaner"
        )
        precondition(bridgeViolations.contains {
            $0.kind == "native integrations during a visual-only edit"
        })
        let oldSchema = #"""
        {"version":1,"purpose":"Legacy","components":[],"storageKeys":[],
         "databaseCollections":[],"nativeMethods":[],"acceptance":[],"recentEdits":[]}
        """#
        let legacy = try! JSONDecoder().decode(ForgeSemanticAppModel.self,
                                               from: Data(oldSchema.utf8))
        precondition(legacy.screenIDs == nil && legacy.routeIDs == nil)
        print("Forge semantic app model, short prompt and edit safety checks passed.")
    }
}
