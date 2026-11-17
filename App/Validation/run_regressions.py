#!/usr/bin/env python3
"""Compile regression harnesses from the actual app methods, without UIKit.

Linux runs logic and scheduling checks. macOS additionally runs SQLite/Core
Data persistence checks. Harness fixtures never access the app's user data.
"""
from pathlib import Path
import subprocess
import tempfile
import sys
import os
import platform

APP = Path(__file__).resolve().parents[1]

def read(path): return (APP/path).read_text()

def method(text, signature):
    start = text.index(signature)
    opening = text.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

CHAPTER = 'import Foundation\nprotocol KVCObject {}\n' + read('Shared/Old Models/Chapter.swift')
READER = read('iOS/UI/Reader/ReaderViewController.swift')

def run(name, source):
    with tempfile.TemporaryDirectory(prefix='yoru-regression-') as directory:
        root = Path(directory)
        path = root/(name+'.swift'); path.write_text(source)
        env = dict(os.environ)
        compiler = ['swiftc']
        if sys.platform == 'darwin':
            # A build phase inherits the iPhone SDK. These are host-side test
            # executables, so select the Mac SDK and target explicitly.
            for key in ['SDKROOT','SDK_VARIANT','IPHONEOS_DEPLOYMENT_TARGET','MACOSX_DEPLOYMENT_TARGET','DYLD_LIBRARY_PATH','DYLD_FRAMEWORK_PATH']:
                env.pop(key, None)
            sdk = subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],env=env,text=True).strip()
            swift = subprocess.check_output(['xcrun','-f','swiftc'],env=env,text=True).strip()
            compiler = [swift, '-sdk', sdk, '-target', platform.machine()+'-apple-macosx14.0']
        subprocess.run([*compiler,'-swift-version','5','-parse-as-library',str(path),'-o',str(root/name)],env=env,check=True)
        subprocess.run([str(root/name)],env=env,check=True,timeout=30)

def navigation():
    methods = '\n'.join(method(READER, 'func '+signature) for signature in ['getNextChapter()','getPreviousChapter()'])
    run('Navigation', CHAPTER + r'''
class AidokuStorage { static let defaults = UserDefaults(suiteName:"yoru.regression.navigation")! }
class CoreDataManager {
 static let shared = CoreDataManager()
 var language:String?
 struct Filters {let language:String?}
 func getMangaChapterFilters(sourceId:String,mangaId:String)->Filters {Filters(language:language)}
}
class ReaderHarness {
 var chapter:Chapter;var chapterList:[Chapter]
 init(_ c:Chapter,_ list:[Chapter]){chapter=c;chapterList=list}
''' + methods + r'''
}
func c(_ id:String,_ number:Float?,_ title:String?=nil,_ lang:String="en")->Chapter {
 Chapter(sourceId:"s",id:id,mangaId:"m",title:title,lang:lang,chapterNum:number,sourceOrder:0)
}
@main struct Run {
 static func main() {
  defer{AidokuStorage.defaults.removePersistentDomain(forName:"yoru.regression.navigation")}
  AidokuStorage.defaults.set(true,forKey:"Reader.skipDuplicateChapters")
  let first=c("1",1,"Chapter 1"), duplicate=c("dup",1,"chapter 1")
  let extra=c("plus",1,"Chapter 1+1.2"), decimal=c("1.2",1.2), next=c("2",2)
  let reader=ReaderHarness(first,[next,decimal,extra,duplicate,first])
  assert(reader.getNextChapter()?.id=="plus")
  reader.chapter=extra;assert(reader.getNextChapter()?.id=="1.2")
  assert(reader.getPreviousChapter()?.id=="dup")
  reader.chapter=first
  AidokuStorage.defaults.set(false,forKey:"Reader.skipDuplicateChapters")
  assert(reader.getNextChapter()?.id=="dup")
  reader.chapter=duplicate;assert(reader.getPreviousChapter()?.id=="1")
  assert(!c("unnumbered-a",nil).isDuplicateRelease(of:c("unnumbered-b",nil)))
  assert(!c("bonus-a",1,"Bonus").isDuplicateRelease(of:c("bonus-b",1,"Bonus")))
  assert(!c("1.1",1.1).isDuplicateRelease(of:decimal))
  let blank=c("blank",1,"Chapter 1+1.2","")
  reader.chapter=first;reader.chapterList=[next,blank,first]
  assert(reader.getNextChapter()?.id=="blank")
  reader.chapter=blank;assert(reader.getNextChapter()?.id=="2")
  let french=c("fr",2,nil,"fr")
  reader.chapter=first;reader.chapterList=[next,french,blank,first]
  assert(reader.getNextChapter()?.id=="2")
  CoreDataManager.shared.language="fr"
  assert(reader.getNextChapter()?.id=="fr")
  let chapters=(1...12).reversed().map{c(String($0),Float($0))}
  var history:[String:(page:Int,date:Int)]=["1":(-1,10),"11":(3,20)]
  assert(Chapter.nextReadingChapter(newestFirst:chapters,history:history)?.id=="11")
  history["11"]=(-1,20)
  assert(Chapter.nextReadingChapter(newestFirst:chapters,history:history)?.id=="12")
  assert(Chapter.nextReadingChapter(newestFirst:chapters,history:["1":(-1,10)])?.id=="2")
  assert(Chapter.nextReadingChapter(newestFirst:chapters,history:Dictionary(uniqueKeysWithValues:chapters.map{($0.id,(page:-1,date:1))}))==nil)
  assert(!first.matchesReadingLanguage(of:french,preferredLanguage:nil,availableChapters:[first,french]))
  print("PASS: extras/decimal navigation, language streams and latest-session resume")
 }
}
''')

def reader_saves():
    methods = '\n'.join(method(READER, 'func '+signature) for signature in ['updateReadPosition(', 'setChapter(', 'setCurrentPage(', 'setTotalPages(', 'setCompleted()'])
    run('ReaderSaves', CHAPTER + r'''
class Manga {}
class AidokuStorage {static let defaults=UserDefaults(suiteName:"yoru.regression.saves")!}
@MainActor class ReadingSaveBackgroundTask {func finish(){}}
class Toolbar {
 var currentPage:Int?;var totalPages:Int?
 func updateSliderPosition(){}
}
class ActivityIndicator {func stopAnimating(){}}
class DownloadManager {static let shared=DownloadManager();func delete(chapters:[Chapter]){}}
actor HistoryManager {
 static let shared=HistoryManager()
 struct Saved {let id:String;let page:Int;let total:Int?;let completed:Bool}
 var records:[Saved]=[]
 func setProgress(chapter:Chapter,progress:Int,totalPages:Int?,completed:Bool,manga:Manga?) async -> Bool {
  try? await Task.sleep(nanoseconds:10_000_000)
  records.append(Saved(id:chapter.id,page:progress,total:totalPages,completed:completed));return true
 }
}
@MainActor class ReaderHarness {
 var chapter:Chapter
 var currentPage=0
 let mangaMetadata:Manga?=nil
 var progressSaveTask:Task<Void,Never>?
 var lastQueuedProgress:String?
 var toolbarView=Toolbar()
 var activityIndicator=ActivityIndicator()
 init(_ c:Chapter){chapter=c}
 func loadNavbarTitle(){}
''' + methods + r'''
}
func c(_ id:String)->Chapter {Chapter(sourceId:"s",id:id,mangaId:"m",title:id,sourceOrder:0)}
@main struct Run {
 @MainActor static func main() async {
  defer{AidokuStorage.defaults.removePersistentDomain(forName:"yoru.regression.saves")}
  let reader=ReaderHarness(c("1"))
  // Entering a chapter must save its initial page even when the page
  // controller never reports a did-scroll event for its starting position.
  reader.setTotalPages(10)
  await reader.progressSaveTask?.value
  var records=await HistoryManager.shared.records
  assert(records.count==1 && records[0].id=="1" && records[0].page==1)
  reader.setCurrentPage(4)
  reader.setChapter(c("2"));reader.setTotalPages(20)
  await reader.progressSaveTask?.value
  reader.setCurrentPage(7)
  await reader.progressSaveTask?.value
  records=await HistoryManager.shared.records
  assert(records.count==4 && records[0].id=="1" && records[0].page==1)
  assert(records[1].id=="1" && records[1].page==4)
  assert(records[2].id=="2" && records[2].page==1 && records[2].total==20)
  assert(records[3].id=="2" && records[3].page==7 && records[3].total==20)
  reader.setCurrentPage(20);await reader.progressSaveTask?.value
  records=await HistoryManager.shared.records;assert(records.last!.completed)
  reader.setChapter(c("3"));reader.toolbarView.totalPages=10;reader.setCurrentPage(1)
  await reader.progressSaveTask?.value
  records=await HistoryManager.shared.records;assert(records.last!.id=="3" && records.last!.page==1)
  let count=records.count
  AidokuStorage.defaults.set(true,forKey:"General.incognitoMode")
  reader.setCurrentPage(2);await reader.progressSaveTask?.value
  records=await HistoryManager.shared.records;assert(records.count==count)
  AidokuStorage.defaults.set(false,forKey:"General.incognitoMode")
  reader.setChapter(c("unloaded"));reader.updateReadPosition()
  await reader.progressSaveTask?.value
  records=await HistoryManager.shared.records;assert(!records.contains{$0.id=="unloaded"})
  print("PASS: chapter snapshots, ordered saves, completion, first-page history and incognito")
 }
}
''')

def yoru_library():
    library = read('Yoru/Library.swift').split('@Observable @MainActor final class CatalogStore')[0]
    run('YoruLibrary', read('Yoru/Anime.swift') + read('Yoru/Journal.swift') + library + r'''
@main struct Run {
 @MainActor static func main() throws {
  let domain="yoru.regression.library."+UUID().uuidString
  let defaults=UserDefaults(suiteName:domain)!
  defer{defaults.removePersistentDomain(forName:domain)}
  let anime=Anime(malId:1,title:"Test",episodes:12)
  var library=Library(defaults:defaults)
  library.toggle(anime);library.log(anime)
  var restored=Library(defaults:defaults)
  assert(restored.isSaved(anime) && restored.watched(anime)==1)
  var note=JournalEntry();note.title="Test note"
  try library.saveJournal(note,for:anime)
  restored=Library(defaults:defaults);assert(restored.journal(for:anime).count==1)
  let corrupt=Data("broken library".utf8)
  defaults.set(corrupt,forKey:"yoru.library.v3")
  library=Library(defaults:defaults)
  assert(library.saveError != nil)
  library.toggle(anime);library.log(anime)
  assert(library.entries.isEmpty)
  assert(defaults.data(forKey:"yoru.library.v3")==corrupt)
  do {try library.saveJournal(note,for:anime);assertionFailure("corrupt storage accepted a save")}catch LibraryValidation.storageUnavailable {}
  print("PASS: Yoru relaunch persistence, journal round trip and corrupt-data protection")
 }
}
''')

def page_cache():
    text = read('iOS/UI/Reader/Readers/Paged/ReaderPagedViewModel.swift')
    methods = '\n'.join(method(text, 'func '+signature) for signature in ['loadPages(chapter:', 'preload(chapter:'])
    run('PageCache', CHAPTER + r'''
struct Page {let chapterID:String}
class SourceManager {
 static let shared=SourceManager()
 func source(for id:String)->SourceManager?{self}
 func getPageListWithoutContents(chapter:Chapter) async throws -> [Page] {
  try await Task.sleep(nanoseconds:chapter.id=="slow" ? 100_000_000 : 1_000_000)
  return [Page(chapterID:chapter.id)]
 }
}
@MainActor class CacheHarness {
 var chapter:Chapter?;var pages:[Page]=[]
 var preloadedChapter:Chapter?;var preloadedPages:[Page]=[]
 var loadGeneration=UUID();var preloadGeneration=UUID()
''' + methods + r'''
}
func c(_ id:String)->Chapter{Chapter(sourceId:"s",id:id,mangaId:"m",title:id,sourceOrder:0)}
@main struct Run {
 @MainActor static func main() async {
  let cache=CacheHarness()
  await cache.loadPages(chapter:c("A"));await cache.loadPages(chapter:c("B"))
  assert(cache.chapter?.id=="B" && cache.pages.first?.chapterID=="B")
  assert(cache.preloadedChapter?.id=="A" && cache.preloadedPages.first?.chapterID=="A")
  await cache.loadPages(chapter:c("A"))
  assert(cache.chapter?.id=="A" && cache.pages.first?.chapterID=="A")
  assert(cache.preloadedChapter?.id=="B" && cache.preloadedPages.first?.chapterID=="B")
  let slow=Task{@MainActor in await cache.loadPages(chapter:c("slow"))}
  try? await Task.sleep(nanoseconds:10_000_000)
  await cache.loadPages(chapter:c("fast"));await slow.value
  assert(cache.chapter?.id=="fast" && cache.pages.first?.chapterID=="fast")
  print("PASS: chapter page cache identity and stale-load rejection")
 }
}
''')

def disabled_preload():
    callback = method(read('iOS/UI/Reader/Readers/Paged/ReaderPagedViewController.swift'), 'func pageViewController(\n        _ pageViewController: UIPageViewController,\n        didFinishAnimating')
    run('DisabledPreload', CHAPTER + r'''
class UIViewController {}
class UIPageViewController {var viewControllers:[UIViewController]?=[UIViewController()]}
class PageController {func setPage(_ page:Int,sourceId:String){}}
class PageModel {
 var pages=Array(1...10);var preloadedPages=[Int]()
 func preload(chapter:Chapter) async {}
}
class Delegate {var page=0;func setCurrentPage(_ page:Int){self.page=page}}
@MainActor class PagedHarness {
 enum Position {case first}
 var pagesToPreload=0;var previousChapter:Chapter?;var nextChapter:Chapter?
 var currentPage=0;var usesDoublePages=false
 var viewModel=PageModel();var delegate:Delegate?=Delegate()
 var pageViewControllers=[PageController]()
 func getIndex(of vc:UIViewController,pos:Position)->Int?{3}
 func loadPreviousChapter(){};func loadNextChapter(){}
 func loadPages(in range:ClosedRange<Int>){}
''' + callback + r'''
}
@main struct Run {
 @MainActor static func main() {
  let reader=PagedHarness()
  reader.pageViewController(UIPageViewController(),didFinishAnimating:true,previousViewControllers:[],transitionCompleted:true)
  assert(reader.currentPage==3 && reader.delegate?.page==3)
  print("PASS: page updates remain enabled with zero preloading")
 }
}
''')

def duplicate_history():
    body = method(read('Shared/Managers/CoreData/CoreDataManager+History.swift'), 'func getReadingHistory(')
    run('DuplicateHistory', r'''
import Foundation
class Metadata {}
class HistoryRow {
 var chapterId="chapter";var completed=false;var progress:Int16=0;var total:Int16=10
 var dateRead:Date?;var chapter:Metadata?;var deleted=false
}
typealias HistoryObject = HistoryRow
class Context {func delete(_ row:HistoryRow){row.deleted=true};func save() throws {}}
class Container {let context=Context();func performBackgroundTask<T>(_ body:(Context)->T) async -> T {body(context)}}
class CoreDataHarness {
 let container=Container();var rows:[HistoryRow]=[]
 func getHistoryForManga(sourceId:String,mangaId:String,context:Context)->[HistoryRow]{rows.filter{!$0.deleted}}
 func hasLibraryManga(sourceId:String,mangaId:String,context:Context)->Bool{false}
 func getChapter(sourceId:String,mangaId:String,chapterId:String,context:Context)->Metadata?{nil}
''' + body + r'''
}
@main struct Run {
 static func main() async {
  let manager=CoreDataHarness()
  let older=HistoryRow();older.completed=true;older.progress=10;older.dateRead=Date(timeIntervalSince1970:10)
  let newer=HistoryRow();newer.progress=5;newer.dateRead=Date(timeIntervalSince1970:20)
  manager.rows=[older,newer]
  let history=await manager.getReadingHistory(sourceId:"s",mangaId:"m")
  assert(history["chapter"]?.page == -1 && history["chapter"]?.date == 20)
  assert(older.progress==5 && older.completed && newer.deleted)
  print("PASS: duplicate history repair retains completion and newer progress")
 }
}
''')

def coredata():
    if sys.platform != 'darwin':
        print('SKIP: SQLite/Core Data durability checks require macOS', flush=True)
        return
    save = method(read('Shared/Managers/Manga/HistoryManager.swift'), 'func setProgress(')
    set_progress = method(read('Shared/Managers/CoreData/CoreDataManager+History.swift'), 'func setProgress(')
    run('CoreDataPersistence', CHAPTER + r'''
import CoreData
class Manga {let sourceId:String;let id:String;let title:String?
 init(sourceId:String,id:String,title:String?=nil){self.sourceId=sourceId;self.id=id;self.title=title}}
class LogManager {static let logger=LogManager();func error(_ message:String){print(message)}}
actor TrackerManager {static let shared=TrackerManager();func setCompleted(chapter:Chapter){}}
@objc(RegressionRecord) class Record:NSManagedObject {
 @NSManaged var id:String
 @NSManaged var title:String?
 @NSManaged var sourceId:String
 @NSManaged var mangaId:String
 @NSManaged var chapterId:String
 @NSManaged var progress:Int16
 @NSManaged var total:Int16
 @NSManaged var completed:Bool
 @NSManaged var dateRead:Date?
}
class SaveContext:NSManagedObjectContext {
 var failNext=false
 override func save() throws {
  if failNext {failNext=false;throw NSError(domain:"ExpectedSaveFailure",code:1)}
  try super.save()
 }
}
let storeURL=FileManager.default.temporaryDirectory.appendingPathComponent("YoruHistoryTest-"+UUID().uuidString+".sqlite")
class CoreDataManager {
 static var shared=CoreDataManager()
 let container:NSPersistentContainer
 init(){
  func entity(_ name:String,_ columns:[(String,NSAttributeType)])->NSEntityDescription {
   let e=NSEntityDescription();e.name=name;e.managedObjectClassName=NSStringFromClass(Record.self)
   e.properties=columns.map{ name,kind in
    let a=NSAttributeDescription();a.name=name;a.attributeType=kind;a.isOptional=true;return a
   };return e
  }
  let model=NSManagedObjectModel()
  model.entities=[
   entity("Manga",[("sourceId",.stringAttributeType),("id",.stringAttributeType),("title",.stringAttributeType)]),
   entity("Chapter",[("sourceId",.stringAttributeType),("mangaId",.stringAttributeType),("id",.stringAttributeType),("title",.stringAttributeType)]),
   entity("History",[("sourceId",.stringAttributeType),("mangaId",.stringAttributeType),("chapterId",.stringAttributeType),("progress",.integer16AttributeType),("total",.integer16AttributeType),("completed",.booleanAttributeType),("dateRead",.dateAttributeType)])]
  container=NSPersistentContainer(name:"Regression",managedObjectModel:model)
  let description=NSPersistentStoreDescription(url:storeURL);description.shouldAddStoreAsynchronously=false
  container.persistentStoreDescriptions=[description]
  container.loadPersistentStores{_,error in precondition(error==nil,String(describing:error))}
 }
 func records(_ entity:String,_ context:NSManagedObjectContext)->[Record] {
  try! context.fetch(NSFetchRequest<Record>(entityName:entity))
 }
 func getManga(sourceId:String,mangaId:String,context:NSManagedObjectContext)->Record? {
  records("Manga",context).first{$0.sourceId==sourceId && $0.id==mangaId}
 }
 func getOrCreateManga(_ manga:Manga,context:NSManagedObjectContext)->Record {
  if let existing=getManga(sourceId:manga.sourceId,mangaId:manga.id,context:context){return existing}
  let row=NSEntityDescription.insertNewObject(forEntityName:"Manga",into:context) as! Record
  row.sourceId=manga.sourceId;row.id=manga.id;row.title=manga.title;return row
 }
 func hasChapter(sourceId:String,mangaId:String,chapterId:String,context:NSManagedObjectContext)->Bool {
  records("Chapter",context).contains{$0.sourceId==sourceId && $0.mangaId==mangaId && $0.id==chapterId}
 }
 func createChapter(_ chapter:Chapter,mangaObject:Record,context:NSManagedObjectContext) {
  let row=NSEntityDescription.insertNewObject(forEntityName:"Chapter",into:context) as! Record
  row.sourceId=chapter.sourceId;row.mangaId=chapter.mangaId;row.id=chapter.id;row.title=chapter.title
 }
 func getOrCreateHistory(sourceId:String,mangaId:String,chapterId:String,context:NSManagedObjectContext?)->Record {
  let context=context!
  if let row=records("History",context).first(where:{$0.sourceId==sourceId && $0.mangaId==mangaId && $0.chapterId==chapterId}){return row}
  let row=NSEntityDescription.insertNewObject(forEntityName:"History",into:context) as! Record
  row.sourceId=sourceId;row.mangaId=mangaId;row.chapterId=chapterId;row.progress=0;row.total=0;row.completed=false
  return row
 }
 func setRead(sourceId:String,mangaId:String,context:NSManagedObjectContext){}
''' + set_progress + r'''
}
class HistoryHarness {
 let writingContext:SaveContext
 init(){
  writingContext=SaveContext(concurrencyType:.privateQueueConcurrencyType)
  writingContext.persistentStoreCoordinator=CoreDataManager.shared.container.persistentStoreCoordinator
 }
''' + save + r'''
}
func c(_ n:Int)->Chapter{Chapter(sourceId:"s",id:String(n),mangaId:"m",title:"Chapter \(n)",chapterNum:Float(n),sourceOrder:0)}
@main struct Run {
 @MainActor static func main() async throws {
  defer{
   for suffix in ["","-wal","-shm"] {try? FileManager.default.removeItem(atPath:storeURL.path+suffix)}
  }
  var writer=HistoryHarness()
  let manga=Manga(sourceId:"s",id:"m",title:"Offline book")
  for n in 1...10 {
   let saved=await writer.setProgress(chapter:c(n),progress:10,totalPages:10,manga:manga)
   assert(saved)
  }
  let saved=await writer.setProgress(chapter:c(11),progress:3,totalPages:20,manga:manga)
  assert(saved)
  let old=CoreDataManager.shared
  await writer.writingContext.perform{writer.writingContext.reset()}
  for store in old.container.persistentStoreCoordinator.persistentStores {try old.container.persistentStoreCoordinator.remove(store)}
  CoreDataManager.shared=CoreDataManager();writer=HistoryHarness()
  let context=CoreDataManager.shared.container.viewContext
  let history=CoreDataManager.shared.records("History",context)
  assert(history.count==11)
  assert(history.filter{$0.completed}.count==10)
  assert(history.first{$0.chapterId=="11"}?.progress==3)
  assert(CoreDataManager.shared.records("Manga",context).first?.title=="Offline book")
  assert(CoreDataManager.shared.records("Chapter",context).count==11)
  await writer.writingContext.perform{writer.writingContext.failNext=true}
  let failed=await writer.setProgress(chapter:c(12),progress:1,totalPages:20,manga:manga)
  assert(!failed)
  let fresh=CoreDataManager.shared.container.newBackgroundContext()
  let count=await fresh.perform{CoreDataManager.shared.records("History",fresh).count}
  assert(count==11)
  let retry=await writer.setProgress(chapter:c(12),progress:1,totalPages:20,manga:manga)
  assert(retry)
  print("PASS: actual HistoryManager saves chapters 1–11 to SQLite, survives store reopening, retains offline metadata and rolls back failed saves")
 }
}
''')

if __name__ == '__main__':
    navigation()
    reader_saves()
    yoru_library()
    page_cache()
    disabled_preload()
    duplicate_history()
    coredata()
