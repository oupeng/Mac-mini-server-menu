import Foundation

let service = try WebSocketService(port: 29876)
service.start()
RunLoop.main.run()
