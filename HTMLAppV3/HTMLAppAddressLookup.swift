import Foundation
import CoreLocation

/// Reverse geocodes coordinates only after the saved app's location consent.
@MainActor
enum HTMLAppAddressLookup {
    static func reverse(latitude: Double, longitude: Double) async throws -> [String: Any] {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            throw LookupError.invalidCoordinates
        }
        let geocoder = CLGeocoder()
        let marks = try await geocoder.reverseGeocodeLocation(
            CLLocation(latitude: latitude, longitude: longitude))
        guard let mark = marks.first else { throw LookupError.noAddress }
        let number = mark.subThoroughfare ?? ""
        let road = mark.thoroughfare ?? ""
        let street = [number, road].filter { !$0.isEmpty }.joined(separator: " ")
        let display = [
            street, mark.locality ?? "", mark.administrativeArea ?? "",
            mark.postalCode ?? "", mark.country ?? ""
        ].filter { !$0.isEmpty }.joined(separator: ", ")
        guard !display.isEmpty else { throw LookupError.noAddress }
        return [
            "formattedAddress": display,
            "street": street,
            "houseNumber": number,
            "road": road,
            "city": mark.locality ?? "",
            "region": mark.administrativeArea ?? "",
            "postalCode": mark.postalCode ?? "",
            "country": mark.country ?? "",
            "source": "Apple CoreLocation reverse geocoding",
            "approximate": true
        ]
    }
    enum LookupError: LocalizedError {
        case invalidCoordinates, noAddress
        var errorDescription: String? {
            switch self {
            case .invalidCoordinates: return "Latitude or longitude is invalid."
            case .noAddress: return "No street address is available at these coordinates."
            }
        }
    }
}
