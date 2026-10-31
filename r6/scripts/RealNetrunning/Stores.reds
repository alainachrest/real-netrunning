// -----------------------------------------------------------------------------
// Real Netrunning - other mods' stores and sites
// -----------------------------------------------------------------------------
//
// Virtual Atelier: every registered store is read from its stores system and
// shown as pages in the desktop Browser (shop://), where items can be bought.
//
// Browser Extension: every site other mods add to a computer is listed on the
// portal, and its pages are embedded live inside the desktop Browser.
//
// Vanilla sites from the journal are listed too; those open in the computer's
// own browser.
//
// Both mods are optional. Everything that touches them is compiled only when
// they are installed, so Real Netrunning works with or without them.

module RealNetrunning

@if(ModuleExists("VirtualAtelier.Systems"))
import VirtualAtelier.Systems.*
@if(ModuleExists("BrowserExtension.System"))
import BrowserExtension.System.*
@if(ModuleExists("BrowserExtension.System"))
import BrowserExtension.DataStructures.*

public class RNStoreItem {
    public let tdbid: String;
    public let name: String;
    public let price: Int32;
    public let quantity: Int32;
    public let quality: String;
}

public class RNStore {
    public let id: String;
    public let name: String;
    public let items: array<ref<RNStoreItem>>;
}

public class RNModSite {
    public let address: String;
    public let name: String;
    public let kind: Int32; // 1 = Browser Extension site (embedded), 2 = vanilla site (computer's browser)
}

// --- items and money -----------------------------------------------------------

public func RNItemName(tdbid: String) -> String {
    let record = TweakDBInterface.GetItemRecord(TDBID.Create(tdbid));
    if !IsDefined(record) {
        return "";
    }
    // the item's own name in the player's language
    let name = GetLocalizedTextByKey(record.DisplayName());
    return StrLen(name) > 0 ? name : tdbid;
}

// The store's price, or the game's own price when the store gives none.
public func RNItemPrice(game: GameInstance, tdbid: String, price: Int32, quantity: Int32) -> Int32 {
    if price > 0 {
        return price;
    }
    let player = GetPlayer(game);
    let itemID = ItemID.FromTDBID(TDBID.Create(tdbid));
    if !IsDefined(player) || !ItemID.IsValid(itemID) {
        return 0;
    }
    return RPGManager.CalculateBuyPrice(game, player, itemID, 1.0) * Max(1, quantity);
}

// Returns "ok:<message>" or "err:<message>".
public func RNBuyItem(game: GameInstance, tdbid: String, quantity: Int32, price: Int32) -> String {
    let player = GetPlayer(game);
    let itemID = ItemID.FromTDBID(TDBID.Create(tdbid));
    if !IsDefined(player) || !ItemID.IsValid(itemID) {
        return "err:That item doesn't exist in this game.";
    }
    let transactions = GameInstance.GetTransactionSystem(game);
    let money = transactions.GetItemQuantity(player, MarketSystem.Money());
    if money < price {
        return "err:Not enough eddies. You have " + IntToString(money) + ", it costs " + IntToString(price) + ".";
    }
    transactions.GiveItem(player, itemID, Max(1, quantity));
    if price > 0 {
        transactions.RemoveItemByTDBID(player, t"Items.money", price);
    }
    let name = RNItemName(tdbid);
    return "ok:Bought " + name + " for " + IntToString(price) + " eddies. It's in your inventory.";
}

// --- Virtual Atelier -----------------------------------------------------------

@if(ModuleExists("VirtualAtelier.Systems"))
public func RNAtelierInstalled() -> Bool {
    return true;
}

@if(!ModuleExists("VirtualAtelier.Systems"))
public func RNAtelierInstalled() -> Bool {
    return false;
}

@if(ModuleExists("VirtualAtelier.Systems"))
public func RNReadAtelierStores(game: GameInstance) -> array<ref<RNStore>> {
    let result: array<ref<RNStore>>;
    let manager = VirtualAtelierStoresManager.GetInstance(game);
    if !IsDefined(manager) {
        return result;
    }
    if manager.GetStoresCount() == 0 {
        // stores register through an event; they'll be there next time
        manager.BuildStoresList();
        return result;
    }
    for shop in manager.GetStores() {
        let store = new RNStore();
        store.id = NameToString(shop.storeID);
        store.name = shop.storeName;
        let i = 0;
        while i < ArraySize(shop.items) {
            let name = RNItemName(shop.items[i]);
            if StrLen(name) > 0 {
                let item = new RNStoreItem();
                item.tdbid = shop.items[i];
                item.name = name;
                item.quantity = 1;
                if i < ArraySize(shop.quantities) {
                    if shop.quantities[i] > 0 {
                        item.quantity = shop.quantities[i];
                    }
                }
                let price = 0;
                if i < ArraySize(shop.prices) {
                    price = shop.prices[i];
                }
                item.price = RNItemPrice(game, item.tdbid, price, item.quantity);
                if i < ArraySize(shop.qualities) {
                    item.quality = shop.qualities[i];
                }
                ArrayPush(store.items, item);
            }
            i += 1;
        }
        ArrayPush(result, store);
    }
    return result;
}

@if(!ModuleExists("VirtualAtelier.Systems"))
public func RNReadAtelierStores(game: GameInstance) -> array<ref<RNStore>> {
    let result: array<ref<RNStore>>;
    return result;
}

// --- Browser Extension -----------------------------------------------------------

@if(ModuleExists("BrowserExtension.System"))
public func RNReadExtensionSites(device: ref<GameObject>) -> array<ref<RNModSite>> {
    let result: array<ref<RNModSite>>;
    if !IsDefined(device) {
        return result;
    }
    let system = BrowserExtensionSystem.GetInstance(device);
    if !IsDefined(system) || !system.IsEnabled() {
        return result;
    }
    for data in system.GetSitesData(device) {
        let site = new RNModSite();
        site.address = data.address;
        site.name = GetLocalizedText(data.shortName);
        if StrLen(site.name) == 0 {
            site.name = data.address;
        }
        site.kind = 1;
        ArrayPush(result, site);
    }
    return result;
}

@if(!ModuleExists("BrowserExtension.System"))
public func RNReadExtensionSites(device: ref<GameObject>) -> array<ref<RNModSite>> {
    let result: array<ref<RNModSite>>;
    return result;
}

// A page from a Browser Extension site, or null when no site serves that address.
@if(ModuleExists("BrowserExtension.System"))
public func RNExtensionPage(device: ref<GameObject>, address: String) -> ref<inkCompoundWidget> {
    if !IsDefined(device) {
        return null;
    }
    let system = BrowserExtensionSystem.GetInstance(device);
    if !IsDefined(system) || !system.IsEnabled() {
        return null;
    }
    return system.GetWebPage(address, device);
}

@if(!ModuleExists("BrowserExtension.System"))
public func RNExtensionPage(device: ref<GameObject>, address: String) -> ref<inkCompoundWidget> {
    return null;
}

// --- vanilla sites ---------------------------------------------------------------

public func RNReadJournalSites(game: GameInstance) -> array<ref<RNModSite>> {
    let result: array<ref<RNModSite>>;
    let journal = GameInstance.GetJournalManager(game);
    if !IsDefined(journal) {
        return result;
    }
    let context: JournalRequestContext;
    context.stateFilter.active = true;
    let entries: array<wref<JournalEntry>>;
    journal.GetInternetSites(context, entries);
    for entry in entries {
        let siteEntry = entry as JournalInternetSite;
        if IsDefined(siteEntry) && !siteEntry.IsIgnoredAtDesktop() {
            let main = journal.GetMainInternetPage(siteEntry);
            if IsDefined(main) {
                let site = new RNModSite();
                site.address = main.GetAddress();
                site.name = GetLocalizedText(siteEntry.GetShortName());
                if StrLen(site.name) == 0 || StrLen(site.name) > 40 {
                    site.name = site.address;
                }
                site.kind = 2;
                ArrayPush(result, site);
            }
        }
    }
    return result;
}

// The computer's own browser, so desktops can open vanilla sites in it.
@addField(BrowserController)
public let m_rnOwner: wref<GameObject>;

@wrapMethod(BrowserController)
public func Init(gameController: ref<BrowserGameController>) {
    wrappedMethod(gameController);
    this.m_rnOwner = gameController.GetOwnerEntity() as GameObject;
    let service = DeckService.Get();
    if IsDefined(service) {
        service.RegisterComputerBrowser(this);
    }
}

@addMethod(BrowserController)
public func RNLoad(address: String) {
    this.LoadWebPage(address);
}

// Links clicked inside a page embedded in a desktop Browser go to the computer's
// hidden browser. While that page is shown on the desktop, send them there instead.
@wrapMethod(BrowserController)
private final func LoadWebPage(const address: script_ref<String>) {
    let service = DeckService.Get();
    let device = this.m_gameController.GetOwnerEntity() as GameObject;
    if IsDefined(service) && service.RouteBrowserLink(device, "" + address) {
        return;
    }
    wrappedMethod(address);
}
