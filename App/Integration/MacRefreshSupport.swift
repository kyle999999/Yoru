// SPDX-License-Identifier: GPL-3.0-only
#if targetEnvironment(macCatalyst)
import UIKit
protocol MacRefreshTarget: AnyObject { func refreshMacContent() }
extension LibraryViewController: MacRefreshTarget { func refreshMacContent() { updateLibraryRefresh() } }
extension BrowseViewController: MacRefreshTarget { func refreshMacContent() { refreshSourceLists() } }
extension SourceViewController: MacRefreshTarget { func refreshMacContent() { refresh() } }
extension MangaViewController: MacRefreshTarget { func refreshMacContent() { refresh() } }
#endif
