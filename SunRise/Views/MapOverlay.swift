import Foundation
import SceneKit
import UIKit
import simd

enum GlobeStyle: String, CaseIterable, Identifiable {
    case realistic = "写实"
    case cartoon = "卡通"
    case pixel = "像素"
    case neon = "霓虹"
    var id: String { rawValue }
}

enum MapOverlay {
    static func point(latitude: Double, longitude: Double, radius: Double = 1.018) -> SCNVector3 {
        let lat = latitude * .pi / 180, lon = longitude * .pi / 180
        return SCNVector3(Float(radius * cos(lat) * sin(lon)), Float(radius * sin(lat)), Float(radius * cos(lat) * cos(lon)))
    }

    static func makeCountries() -> SCNNode {
        let root = SCNNode()
        guard let url = Bundle.main.url(forResource: "countries", withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let collection = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let features = collection["features"] as? [[String: Any]] else { return root }
        var vertices: [SCNVector3] = []
        for feature in features {
            guard let geometry = feature["geometry"] as? [String: Any], let coordinates = geometry["coordinates"] else { continue }
            let polygons: [[[[Double]]]]
            if geometry["type"] as? String == "Polygon", let p = coordinates as? [[[Double]]] { polygons = [p] }
            else if let p = coordinates as? [[[[Double]]]] { polygons = p }
            else { continue }
            for polygon in polygons { for ring in polygon {
                for (a, b) in zip(ring, ring.dropFirst()) where a.count >= 2 && b.count >= 2 {
                    var deltaLon = b[0] - a[0]
                    if deltaLon > 180 { deltaLon -= 360 }
                    if deltaLon < -180 { deltaLon += 360 }
                    let steps = max(1, Int(ceil(max(abs(deltaLon), abs(b[1]-a[1])) / 2)))
                    for step in 0..<steps {
                        let t0 = Double(step)/Double(steps), t1 = Double(step+1)/Double(steps)
                        vertices.append(point(latitude: a[1]+(b[1]-a[1])*t0, longitude: a[0]+deltaLon*t0))
                        vertices.append(point(latitude: a[1]+(b[1]-a[1])*t1, longitude: a[0]+deltaLon*t1))
                    }
                }
            } }
            if let p = feature["properties"] as? [String: Any], let name = p["NAME_ZH"] as? String,
               let rank = p["LABELRANK"] as? Int, rank <= 3,
               let lat = p["LABEL_Y"] as? Double, let lon = p["LABEL_X"] as? Double {
                root.addChildNode(label(name, latitude: lat, longitude: lon, city: false))
            }
        }
        if !vertices.isEmpty {
            // Thin spherical ribbons remain visible on high-density displays, unlike 1-pixel lines.
            root.addChildNode(borderRibbon(vertices, halfWidth: 0.0042, color: UIColor(red: 0.03, green: 0.08, blue: 0.12, alpha: 0.9), order: 2))
            root.addChildNode(borderRibbon(vertices, halfWidth: 0.0018, color: UIColor(red: 1, green: 0.84, blue: 0.56, alpha: 0.95), order: 3))
        }
        return root
    }

    private static func borderRibbon(_ points: [SCNVector3], halfWidth: Float, color: UIColor, order: Int) -> SCNNode {
        var mesh: [SCNVector3] = []
        var indices: [Int32] = []
        mesh.reserveCapacity(points.count * 2)
        indices.reserveCapacity(points.count * 3)
        for index in stride(from: 0, to: points.count - 1, by: 2) {
            let a = SIMD3<Float>(points[index].x, points[index].y, points[index].z)
            let b = SIMD3<Float>(points[index+1].x, points[index+1].y, points[index+1].z)
            let segment = b-a
            guard simd_length_squared(segment) > 0.00000001 else { continue }
            let side = simd_normalize(simd_cross(simd_normalize(a+b), simd_normalize(segment))) * halfWidth
            let base = Int32(mesh.count)
            for v in [a-side, a+side, b-side, b+side] { mesh.append(SCNVector3(v.x, v.y, v.z)) }
            indices += [base, base+1, base+2, base+1, base+3, base+2]
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: mesh)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let material = SCNMaterial(); material.lightingModel = .constant; material.isDoubleSided = true
        material.diffuse.contents = color; material.readsFromDepthBuffer = true; material.writesToDepthBuffer = false
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry); node.renderingOrder = order
        return node
    }

    static func makeCities() -> SCNNode {
        let root = SCNNode()
        for city in Solar.cities { root.addChildNode(label(city.name, latitude: city.latitude, longitude: city.longitude, city: true)) }
        return root
    }

    private static func label(_ title: String, latitude: Double, longitude: Double, city: Bool) -> SCNNode {
        let font = UIFont.systemFont(ofSize: city ? 23 : 21, weight: city ? .semibold : .medium)
        let textSize = (title as NSString).size(withAttributes: [.font: font])
        let size = CGSize(width: ceil(textSize.width) + (city ? 34 : 24), height: 38)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 0.02, green: 0.05, blue: 0.09, alpha: city ? 0.82 : 0.64).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
            if city {
                UIColor(red: 1, green: 0.75, blue: 0.43, alpha: 1).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 8, y: 15, width: 8, height: 8))
            }
            (title as NSString).draw(at: CGPoint(x: city ? 23 : 12, y: (size.height-textSize.height)/2), withAttributes: [.font: font, .foregroundColor: UIColor.white])
        }
        let scale = 0.0026
        let plane = SCNPlane(width: size.width * scale, height: size.height * scale)
        let material = SCNMaterial(); material.lightingModel = .constant; material.diffuse.contents = image
        material.isDoubleSided = true; material.writesToDepthBuffer = false; material.readsFromDepthBuffer = false
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.position = point(latitude: latitude, longitude: longitude, radius: 1.025)
        node.name = city ? "city-label" : "country-label"
        node.isHidden = true
        let billboard = SCNBillboardConstraint(); billboard.freeAxes = .all; node.constraints = [billboard]
        node.renderingOrder = city ? 12 : 11
        return node
    }
}
