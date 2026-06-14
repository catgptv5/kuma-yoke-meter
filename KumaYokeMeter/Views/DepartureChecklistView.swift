import SwiftUI

struct DepartureChecklistView: View {
    @AppStorage("checklist.avoidDawnDusk") private var avoidDawnDusk = false
    @AppStorage("checklist.notSolo") private var notSolo = false
    @AppStorage("checklist.soundReady") private var soundReady = false
    @AppStorage("checklist.foodTrash") private var foodTrash = false
    @AppStorage("checklist.retreatSigns") private var retreatSigns = false

    private var checkedCount: Int {
        [avoidDawnDusk, notSolo, soundReady, foodTrash, retreatSigns].filter { $0 }.count
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Label(statusTitle, systemImage: statusIcon)
                        .font(.headline)
                        .foregroundStyle(statusColor)

                    Spacer()

                    Text("\(checkedCount)/5")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("出発前") {
                Toggle(isOn: $avoidDawnDusk) {
                    Label("早朝・夕方ではない", systemImage: "sun.horizon")
                }

                Toggle(isOn: $notSolo) {
                    Label("単独行動ではない", systemImage: "person.2")
                }

                Toggle(isOn: $soundReady) {
                    Label("熊鈴・笛・音出しを準備", systemImage: "bell")
                }

                Toggle(isOn: $foodTrash) {
                    Label("食べ物・ゴミを密閉", systemImage: "takeoutbag.and.cup.and.straw")
                }
            }

            Section("現地判断") {
                Toggle(isOn: $retreatSigns) {
                    Label("フン・足跡・獣臭があれば撤退", systemImage: "figure.walk.departure")
                }
            }

            Section {
                Button(role: .destructive) {
                    avoidDawnDusk = false
                    notSolo = false
                    soundReady = false
                    foodTrash = false
                    retreatSigns = false
                } label: {
                    Label("チェックをリセット", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("出発チェック")
    }

    private var statusTitle: String {
        checkedCount == 5 ? "確認済み" : "未確認あり"
    }

    private var statusMessage: String {
        checkedCount == 5
            ? "準備がそろっていても、安全保証ではありません。現地で異変があれば引き返してください。"
            : "出発前に全部確認してください。迷う項目がある日は、予定変更も選択肢です。"
    }

    private var statusIcon: String {
        checkedCount == 5 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private var statusColor: Color {
        checkedCount == 5 ? .green : .orange
    }
}

#Preview {
    NavigationStack {
        DepartureChecklistView()
    }
}

