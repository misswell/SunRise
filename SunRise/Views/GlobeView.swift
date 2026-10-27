import SwiftUI
import SceneKit
import UIKit

struct GlobeView: UIViewRepresentable {
    let date: Date
    let focus: City?
    let style: GlobeStyle
    let showCountries: Bool
    let showCities: Bool
    let resetToken: Int

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.scene = context.coordinator.scene
        context.coordinator.attach(view)
        view.pointOfView = context.coordinator.camera
        view.allowsCameraControl = false
        view.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:))))
        context.coordinator.update(date: date, focus: focus, style: style, showCountries: showCountries, showCities: showCities, resetToken: resetToken, force: true)
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) { context.coordinator.update(date: date, focus: focus, style: style, showCountries: showCountries, showCities: showCities, resetToken: resetToken) }

    final class Coordinator: NSObject {
        let scene = SCNScene()
        let camera = SCNNode()
        let earth = SCNNode()
        let material = SCNMaterial()
        let countries = MapOverlay.makeCountries()
        let cities = MapOverlay.makeCities()
        var lastStyle: GlobeStyle?
        var lastResetToken = 0
        var spinLink: CADisplayLink?
        var labelLink: CADisplayLink?
        weak var sceneView: SCNView?
        var spinVelocity = CGPoint.zero
        var lastFrameTime: CFTimeInterval = 0
        var lastMinute: Int = .min
        var lastFocus: String?
        var textureTask: Task<Void, Never>?
        var panStart = SCNVector3Zero
        var userMoved = false

        override init() {
            super.init()
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 34
            camera.position = SCNVector3(0, 0, 4.1)
            scene.rootNode.addChildNode(camera)
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.diffuse.magnificationFilter = .linear
            material.diffuse.minificationFilter = .linear
            earth.geometry = Self.sphere()
            earth.geometry?.materials = [material]
            earth.addChildNode(countries)
            earth.addChildNode(cities)
            scene.rootNode.addChildNode(earth)

            let atmosphere = SCNSphere(radius: 1.025)
            atmosphere.segmentCount = 96
            let glow = SCNMaterial()
            glow.lightingModel = .constant
            glow.diffuse.contents = UIColor(red: 0.23, green: 0.62, blue: 0.96, alpha: 0.16)
            glow.transparency = 0.38
            glow.isDoubleSided = false
            glow.writesToDepthBuffer = false
            atmosphere.materials = [glow]
            let halo = SCNNode(geometry: atmosphere)
            scene.rootNode.addChildNode(halo)
        }

        func attach(_ view: SCNView) {
            sceneView = view
            let link = CADisplayLink(target: self, selector: #selector(updateLabels))
            link.preferredFramesPerSecond = 30
            link.add(to: .main, forMode: .common)
            labelLink = link
        }

        @objc func updateLabels() {
            guard let view = sceneView else { labelLink?.invalidate(); labelLink = nil; return }
            let groups = [cities, countries]
            var occupied: [CGRect] = []
            SCNTransaction.begin(); SCNTransaction.disableActions = true
            for group in groups {
                for node in group.childNodes where node.name != nil {
                    guard !group.isHidden, let plane = node.geometry as? SCNPlane else { node.isHidden = true; continue }
                    let world = earth.presentation.convertPosition(node.position, to: nil)
                    // Avoid labels at the limb, where they would spill beyond the silhouette.
                    guard world.z > 0.58 else { node.isHidden = true; continue }
                    let projected = view.projectPoint(world)
                    let pointsPerUnit = view.bounds.height / CGFloat(2 * tan(34.0 * .pi / 360) * (4.1 - Double(world.z)))
                    let size = CGSize(width: plane.width * pointsPerUnit, height: plane.height * pointsPerUnit)
                    let rect = CGRect(x: CGFloat(projected.x) - size.width / 2 - 3, y: CGFloat(projected.y) - size.height / 2 - 3, width: size.width + 6, height: size.height + 6)
                    let visible = view.bounds.contains(rect) && !occupied.contains(where: { $0.intersects(rect) })
                    node.isHidden = !visible
                    if visible { occupied.append(rect) }
                }
            }
            SCNTransaction.commit()
        }

        func update(date: Date, focus: City?, style: GlobeStyle, showCountries: Bool, showCities: Bool, resetToken: Int, force: Bool = false) {
            countries.isHidden = !showCountries
            cities.isHidden = !showCities
            let styleChanged = style != lastStyle
            lastStyle = style
            material.diffuse.magnificationFilter = style == .pixel ? .nearest : .linear
            material.diffuse.minificationFilter = style == .pixel ? .nearest : .linear
            if resetToken != lastResetToken {
                lastResetToken = resetToken
                stopSpin()
                userMoved = false
                if let focus { orient(to: focus) } else {
                    SCNTransaction.begin(); SCNTransaction.animationDuration = 0.9
                    earth.eulerAngles = SCNVector3Zero; SCNTransaction.commit()
                }
            }
            let minute = Int(date.timeIntervalSince1970 / 60)
            if minute != lastMinute || force || styleChanged {
                lastMinute = minute
                textureTask?.cancel()
                let direction = Solar.direction(at: date)
                textureTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    let image = await Task.detached(priority: .userInitiated) { EarthTexture.render(sun: direction, style: style) }.value
                    guard !Task.isCancelled, let self, let image else { return }
                    self.material.diffuse.contents = image
                }
            }
            if let focus, focus.id != lastFocus {
                lastFocus = focus.id
                if !userMoved || force {
                    orient(to: focus)
                }
            }
        }
        func orient(to city: City) {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 1.0
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            earth.eulerAngles = SCNVector3(Float(city.latitude * .pi / 180), Float(-city.longitude * .pi / 180), 0)
            SCNTransaction.commit()
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            if gesture.state == .began {
                stopSpin()
                // Capture the displayed pose if an automatic orientation is still animating.
                earth.eulerAngles = earth.presentation.eulerAngles
                earth.removeAllAnimations()
                panStart = earth.eulerAngles
                userMoved = true
            } else if gesture.state == .changed {
                earth.eulerAngles = SCNVector3(max(-1.4, min(1.4, panStart.x + Float(translation.y) * 0.006)), panStart.y + Float(translation.x) * 0.006, 0)
            } else if gesture.state == .ended {
                let velocity = gesture.velocity(in: gesture.view)
                spinVelocity = CGPoint(x: max(-1800, min(1800, velocity.x)), y: max(-1800, min(1800, velocity.y)))
                lastFrameTime = 0
                let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
                link.add(to: .main, forMode: .common)
                spinLink = link
            } else if gesture.state == .cancelled || gesture.state == .failed { stopSpin() }
        }
        @objc func tick(_ link: CADisplayLink) {
            let dt = lastFrameTime == 0 ? link.duration : min(link.timestamp - lastFrameTime, 0.05)
            lastFrameTime = link.timestamp
            var angles = earth.eulerAngles
            angles.x = max(-1.4, min(1.4, angles.x + Float(spinVelocity.y * dt * 0.006)))
            angles.y += Float(spinVelocity.x * dt * 0.006)
            earth.eulerAngles = angles
            let damping = exp(-3.4 * dt)
            spinVelocity.x *= damping; spinVelocity.y *= damping
            if hypot(spinVelocity.x, spinVelocity.y) < 4 { stopSpin() }
        }
        func stopSpin() {
            spinLink?.invalidate(); spinLink = nil; spinVelocity = .zero; lastFrameTime = 0
        }

        static func sphere() -> SCNGeometry {
            let rows = 96, columns = 192
            var vertices: [SCNVector3] = [], uv: [CGPoint] = [], indices: [Int32] = []
            for y in 0...rows {
                let lat = Double.pi / 2 - Double(y) / Double(rows) * .pi
                for x in 0...columns {
                    let lon = Double(x) / Double(columns) * 2 * .pi - .pi
                    vertices.append(SCNVector3(Float(cos(lat)*sin(lon)), Float(sin(lat)), Float(cos(lat)*cos(lon))))
                    uv.append(CGPoint(x: Double(x)/Double(columns), y: Double(y)/Double(rows)))
                }
            }
            for y in 0..<rows { for x in 0..<columns {
                let a = Int32(y * (columns + 1) + x), b = a + Int32(columns + 1)
                indices += [a, b, a+1, a+1, b, b+1]
            } }
            let source = SCNGeometrySource(vertices: vertices)
            let texture = SCNGeometrySource(textureCoordinates: uv)
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
            return SCNGeometry(sources: [source, texture], elements: [element])
        }
    }
}

private enum EarthTexture {
    static let width = 1024, height = 512
    static func pixels(named name: String) -> [UInt8]? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"), let image = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? bytes : nil
    }
    static let day = pixels(named: "earth-day")
    static let night = pixels(named: "earth-night")
    static func render(sun: SIMD3<Double>, style: GlobeStyle) -> UIImage? {
        guard let day, let night else { return nil }
        var result = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let lat = Double.pi / 2 - (Double(y) + 0.5) / Double(height) * .pi
            let cosLat = cos(lat), sinLat = sin(lat)
            for x in 0..<width {
                let lon = (Double(x) + 0.5) / Double(width) * 2 * .pi - .pi
                let light = cosLat * sin(lon) * sun.x + sinLat * sun.y + cosLat * cos(lon) * sun.z
                let t = max(0, min(1, (light + 0.10) / 0.24))
                let blend = t * t * (3 - 2 * t)
                let twilight = max(0, 1 - abs(light + 0.01) / 0.14) * 0.14
                let i = (y * width + x) * 4
                let sample = style == .pixel ? ((y / 8 * 8) * width + (x / 8 * 8)) * 4 : i
                for channel in 0..<3 {
                    let warm = channel == 0 ? 160.0 : (channel == 1 ? 65.0 : 15.0)
                    var value = Double(day[sample+channel]) * blend + Double(night[sample+channel]) * (1-blend) * 0.85 + twilight * warm
                    if style == .cartoon {
                        value = (value / 38).rounded() * 38
                        value = value * (channel == 2 ? 1.08 : 1.03)
                    } else if style == .pixel {
                        value = (value / 32).rounded() * 32
                    } else if style == .neon {
                        let luminance = (Double(day[sample]) * 0.3 + Double(day[sample+1]) * 0.59 + Double(day[sample+2]) * 0.11) / 255
                        let city = Double(night[sample+channel]) * (1-blend)
                        let palette = channel == 0 ? 0.23 : (channel == 1 ? 0.75 : 1.0)
                        value = (18 + 170 * luminance * blend) * palette + city * (channel == 0 ? 0.85 : 0.65) + twilight * warm
                    }
                    result[i+channel] = UInt8(max(0, min(255, value)))
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(result) as CFData), let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
