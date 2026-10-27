import UIKit
import MapKit

/// Foreground native map for saved HTML apps. Only public MapKit tiles are used.
@MainActor
enum HTMLAppNativeMapPresenter {
    static func show(_ arguments: [String: Any], from presenter: UIViewController) -> Bool {
        guard let region = arguments["region"] as? [String: Any],
              let latitude = region["latitude"] as? Double,
              let longitude = region["longitude"] as? Double,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            return false
        }
        let controller = UIViewController()
        controller.title = "Map"
        controller.view.backgroundColor = .systemBackground
        let map = MKMapView(frame: .zero)
        map.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(map)
        NSLayoutConstraint.activate([
            map.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor),
            map.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
            map.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            map.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor)
        ])
        let latitudeDelta = min(90, max(0.001, region["latitudeDelta"] as? Double ?? 0.08))
        let longitudeDelta = min(180, max(0.001, region["longitudeDelta"] as? Double ?? 0.08))
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                         span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)), animated: false)
        let pins = (arguments["annotations"] as? [[String: Any]] ?? []).prefix(100)
        for pin in pins {
            guard let lat = pin["latitude"] as? Double, let lon = pin["longitude"] as? Double,
                  (-90...90).contains(lat), (-180...180).contains(lon) else { continue }
            let point = MKPointAnnotation()
            point.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            point.title = String((pin["title"] as? String ?? "").prefix(120))
            map.addAnnotation(point)
        }
        // Do not start tracking a saved app's location unless the existing
        // native location consent flow explicitly authorizes that operation.
        let navigation = UINavigationController(rootViewController: controller)
        controller.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak navigation] _ in navigation?.dismiss(animated: true) })
        presenter.present(navigation, animated: true)
        return true
    }
}

