// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(name: "DVTNetwork",

                      platforms: [.macOS(.v10_12),
                                  .iOS(.v10),
                                  .tvOS(.v10),
                                  .watchOS(.v3)],

                      products: [.library(name: "DVTNetwork",
                                          targets: ["DVTNetwork"]),],

                      dependencies: [.package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.4.0")),
                                     .package(url: "https://github.com/darvintang/DVTLoger.git", .upToNextMajor(from: "1.0.0")),
                                     .package(url: "https://github.com/darvintang/DVTObjectMapper.git", .upToNextMajor(from: "4.2.0")),
                                    ],

                      targets: [.target(name: "DVTNetwork",
                                        dependencies: ["Alamofire", "DVTLoger","DVTObjectMapper"],
                                        path: "Sources"),
                                .testTarget(name: "DVTNetworkTests",
                                            dependencies:["DVTNetwork"])
                               ]
)
