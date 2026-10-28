// main.swift
import Foundation

let service = try HTTPService(port: 29876)
service.start()
RunLoop.main.run()
