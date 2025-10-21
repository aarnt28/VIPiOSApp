import SwiftUI

struct HardwareView: View {
    @EnvironmentObject var api: APIClient
    @State private var items: [Hardware] = []
    @State private var total: Int = 0
    @State private var error: String?
    @State private var loading = false
    
    var body: some View {
        NavigationStack {
            List(items) { h in
                VStack(alignment: .leading) {
                    HStack {
                        Text(h.description).font(.headline)
                        Spacer()
                        Text(h.barcode).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        if let sp = h.sales_price { Label("$\(sp)", systemImage: "dollarsign.circle") }
                        if let ac = h.acquisition_cost { Label("Cost: \(ac)", systemImage: "banknote") }
                        if let avg = h.average_unit_cost {
                            Label(String(format: "Avg $%.2f", avg), systemImage: "chart.bar")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let vendors = h.common_vendors, !vendors.isEmpty {
                        Label("Vendors: \(vendors.joined(separator: \", \"))", systemImage: "building.2")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .navigationTitle("Hardware")
            .overlay {
                if loading { ProgressView() }
                if let e = error { Text(e).foregroundStyle(.red) }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .task { await load() }
        }
    }
    
    private func load() async {
        loading = true; defer { loading = false }
        do {
            let res = try await api.listHardware(limit: 200, offset: 0)
            items = res.items
            total = res.total ?? res.items.count
            self.error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
