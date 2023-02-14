// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(name: "DVTNetwork",

                      platforms: [.macOS(.v11),
                                  .iOS(.v13)],

                      products: [.library(name: "DVTNetwork",
                                          targets: ["DVTNetwork"]),],

                      dependencies: [.package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.6.0")),
                                     .package(url: "https://github.com/darvintang/DVTLoger.git", .upToNextMajor(from: "2.0.0")),
                                     .package(url: "https://github.com/darvintang/DVTObjectMapper.git", .upToNextMajor(from: "4.2.0")),
                                    ],

                      targets: [.target(name: "DVTNetwork",
                                        dependencies: ["Alamofire", "DVTLoger","DVTObjectMapper"],
                                        path: "Sources"),
                                .testTarget(name: "DVTNetworkTests",
                                            dependencies:["DVTNetwork"])
                               ]
)
