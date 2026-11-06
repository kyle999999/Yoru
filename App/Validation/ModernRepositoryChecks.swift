// SPDX-License-Identifier: GPL-3.0-only
import Foundation
@main struct ModernRepositoryChecks {
 static func main() throws {
  let data = Data(#"[{"id":"multi.test","name":"Legacy","version":8,"file":"old.aix","icon":"old.png","lang":"multi"},{"id":"multi.test","name":"Modern","version":14,"downloadURL":"sources/new.aix","iconURL":"icons/new.png","languages":["en","ja"],"minAppVersion":"0.7.1"},{"id":"th.example","name":"Thai","version":1,"downloadURL":"sources/th.aix","languages":["th"]}]"#.utf8)
  var entries = try JSONDecoder().decode([ExternalSourceInfo].self, from: data)
  for index in entries.indices { entries[index].sourceUrl = URL(string: "https://aidoku-community.github.io/sources/") }
  for order in [entries, Array(entries.reversed())] {
   let result = ExternalSourceInfo.preferred(order)
   assert(result.count == 2)
   assert(result[0].version == 14 && result[0].modernABI)
   assert(result[0].fileURL?.absoluteString == "https://aidoku-community.github.io/sources/sources/new.aix")
   assert(result[0].imageURL?.absoluteString == "https://aidoku-community.github.io/sources/icons/new.png")
   assert(result[1].lang == "th")
  }
  print("PASS: modern repository schema/URLs/languages and legacy-modern precedence in either completion order")
 }
}
