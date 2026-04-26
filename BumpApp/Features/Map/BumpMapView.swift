import MapKit
import SwiftUI

struct BumpMapView: View {
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 12) {
            Map(position: $cameraPosition) {
                Annotation("Jake", coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)) {
                    Circle()
                        .fill(BumpColors.accent)
                        .frame(width: 16, height: 16)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("Friends who are free and public events appear here.")
                .foregroundStyle(BumpColors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .navigationTitle("Map")
    }
}
