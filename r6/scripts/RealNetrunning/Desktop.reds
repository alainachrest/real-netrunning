// -----------------------------------------------------------------------------
// Real Netrunning - simulated computer desktops
// -----------------------------------------------------------------------------
//
// Adds a DESKTOP button to every in-game computer screen. It switches into a
// simulated OS drawn over the vanilla screen, which stays underneath untouched:
//
//   Files     - the computer's own mail and documents, plus the system files
//               Real Netrunning generates for it (locked until breached)
//   Terminal  - the cyberdeck shell, connected to this computer
//   Deck      - opens the full cyberdeck popup
//
// Generated files come from the Lua mod through DeckService (Deck.reds).

module RealNetrunning
import Codeware.UI.*

// --- small helpers ----------------------------------------------------------

func RNColor(r: Float, g: Float, b: Float, a: Float) -> HDRColor {
    let c: HDRColor;
    c.Red = r;
    c.Green = g;
    c.Blue = b;
    c.Alpha = a;
    return c;
}

func RNText(name: CName, size: Int32, color: CName) -> ref<inkText> {
    let text = new inkText();
    text.SetName(name);
    text.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
    text.SetFontStyle(n"Medium");
    text.SetFontSize(size);
    text.SetFitToContent(true);
    text.SetHAlign(inkEHorizontalAlign.Left);
    text.SetVAlign(inkEVerticalAlign.Top);
    text.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
    text.BindProperty(n"tintColor", color);
    text.SetText(" ");
    return text;
}

func RNRect(name: CName, color: HDRColor) -> ref<inkRectangle> {
    let rect = new inkRectangle();
    rect.SetName(name);
    rect.SetAnchor(inkEAnchor.Fill);
    rect.SetTintColor(color);
    return rect;
}

// Journal titles and contents can be localisation keys.
func RNLocalize(text: String) -> String {
    if StrBeginsWith(text, "LocKey#") {
        return GetLocalizedText(text);
    }
    return text;
}

func RNSafeName(text: String) -> String {
    let name = StrReplaceAll(RNLocalize(text), "/", "-");
    if StrLen(name) == 0 {
        return "untitled";
    }
    return name;
}

// --- the desktop --------------------------------------------------------------

public class RNDesktop {
    // which computer this is
    private let m_controller: wref<ComputerInkGameController>;
    private let m_key: String;
    private let m_name: String;

    // everything shown in the file explorer: vanilla docs, then generated files
    private let m_paths: array<String>;
    private let m_texts: array<String>;
    private let m_locked: array<Bool>;
    private let m_vanillaCount: Int32;

    // widgets
    private let m_desktop: wref<inkCanvas>;
    private let m_window: wref<inkCanvas>;
    private let m_windowTitle: wref<inkText>;
    private let m_header: wref<inkText>;
    private let m_rows: array<wref<inkText>>;
    private let m_footer: wref<inkText>;
    private let m_pager: wref<inkHorizontalPanel>;
    private let m_clock: wref<inkText>;
    private let m_inputRow: wref<inkHorizontalPanel>;
    private let m_prompt: wref<inkText>;
    private let m_input: ref<TextInput>;

    // state
    private let m_mode: Int32;          // 0 closed, 1 files, 2 document, 3 terminal
    private let m_cwd: String;
    private let m_listNames: array<String>;
    private let m_listIsDir: array<Bool>;
    private let m_listIndex: array<Int32>; // file index for files, -1 for folders
    private let m_offset: Int32;
    private let m_docIndex: Int32;
    private let m_docPage: Int32;
    private let m_terminalConnected: Bool;

    private func VisibleRows() -> Int32 { return 12; }
    private func PageChars() -> Int32 { return 900; }

    public static func Create(controller: ref<ComputerInkGameController>, root: ref<inkCompoundWidget>,
                              key: String, name: String, ps: ref<ComputerControllerPS>) -> ref<RNDesktop> {
        let self = new RNDesktop();
        self.m_controller = controller;
        self.m_key = key;
        self.m_name = RNLocalize(name);
        self.m_cwd = "";
        self.LoadVanillaDocuments(ps);
        self.Build(root, controller);

        let service = DeckService.Get();
        if IsDefined(service) {
            service.RegisterTerminal(self);
            service.RequestMachine(key, self.m_name);
        }
        return self;
    }

    // --- data -----------------------------------------------------------------

    private func LoadVanillaDocuments(ps: ref<ComputerControllerPS>) {
        if !IsDefined(ps) {
            return;
        }
        for thumb in ps.GetMailThumbnailWidgets() {
            let doc = ps.GetMailWidget(thumb.documentAdress);
            this.AddDocument("Mail", thumb.folderName, doc);
        }
        for thumb in ps.GetFileThumbnailWidgets() {
            let doc = ps.GetFileWidget(thumb.documentAdress);
            this.AddDocument("Documents", thumb.folderName, doc);
        }
        this.m_vanillaCount = ArraySize(this.m_paths);
    }

    private func AddDocument(root: String, folder: String, doc: SDocumentWidgetPackage) {
        let folderName = StrLen(folder) > 0 ? RNSafeName(folder) : "Inbox";
        let path = root + "/" + folderName + "/" + RNSafeName(doc.title);
        let body = "";
        if StrLen(doc.owner) > 0 {
            body = "From: " + RNLocalize(doc.owner) + "\n";
        }
        if StrLen(doc.date) > 0 {
            body += RNLocalize(doc.date) + "\n";
        }
        body += "\n" + RNLocalize(doc.content);
        ArrayPush(this.m_paths, path);
        ArrayPush(this.m_texts, body);
        ArrayPush(this.m_locked, doc.isEncrypted);
    }

    private func ReloadGeneratedFiles() {
        ArrayResize(this.m_paths, this.m_vanillaCount);
        ArrayResize(this.m_texts, this.m_vanillaCount);
        ArrayResize(this.m_locked, this.m_vanillaCount);
        let service = DeckService.Get();
        if !IsDefined(service) {
            return;
        }
        for entry in service.GetMachineFiles(this.m_key) {
            ArrayPush(this.m_paths, "System" + entry.path);
            ArrayPush(this.m_texts, entry.text);
            ArrayPush(this.m_locked, entry.locked);
        }
    }

    // Lists the folders and files directly inside the current folder.
    private func ListCurrentFolder() {
        ArrayClear(this.m_listNames);
        ArrayClear(this.m_listIsDir);
        ArrayClear(this.m_listIndex);

        let prefix = StrLen(this.m_cwd) > 0 ? this.m_cwd + "/" : "";
        let i = 0;
        while i < ArraySize(this.m_paths) {
            let path = this.m_paths[i];
            if StrLen(prefix) == 0 || StrBeginsWith(path, prefix) {
                let rest = StrMid(path, StrLen(prefix));
                let slash = StrFindFirst(rest, "/");
                if slash < 0 {
                    ArrayPush(this.m_listNames, rest);
                    ArrayPush(this.m_listIsDir, false);
                    ArrayPush(this.m_listIndex, i);
                } else {
                    let folder = StrLeft(rest, slash);
                    if !ArrayContains(this.m_listNames, folder) {
                        ArrayPush(this.m_listNames, folder);
                        ArrayPush(this.m_listIsDir, true);
                        ArrayPush(this.m_listIndex, -1);
                    }
                }
            }
            i += 1;
        }
    }

    // --- building the UI --------------------------------------------------------

    private func Build(root: ref<inkCompoundWidget>, controller: ref<ComputerInkGameController>) {
        // launcher button on the vanilla screen
        let launcher = new inkCanvas();
        launcher.SetName(n"rn_launcher");
        launcher.SetAnchor(inkEAnchor.BottomRight);
        launcher.SetAnchorPoint(Vector2(1.0, 1.0));
        launcher.SetMargin(inkMargin(0.0, 0.0, 30.0, 30.0));
        launcher.SetSize(220.0, 56.0);
        launcher.SetInteractive(true);
        launcher.Reparent(root);
        RNRect(n"bg", RNColor(0.05, 0.05, 0.07, 0.85)).Reparent(launcher);
        let launcherText = RNText(n"label", 30, n"MainColors.Blue");
        launcherText.SetAnchor(inkEAnchor.Centered);
        launcherText.SetAnchorPoint(Vector2(0.5, 0.5));
        launcherText.SetText("DESKTOP");
        launcherText.Reparent(launcher);
        launcher.RegisterToCallback(n"OnRelease", this, n"OnLaunch");

        // the desktop itself, hidden until launched
        let desktop = new inkCanvas();
        desktop.SetName(n"rn_desktop");
        desktop.SetAnchor(inkEAnchor.Fill);
        desktop.SetInteractive(true);
        desktop.SetVisible(false);
        desktop.Reparent(root);
        this.m_desktop = desktop;
        RNRect(n"wallpaper", RNColor(0.02, 0.03, 0.05, 0.97)).Reparent(desktop);

        let title = RNText(n"machine", 34, n"MainColors.Red");
        title.SetMargin(inkMargin(40.0, 30.0, 0.0, 0.0));
        title.SetText(StrUpper(this.m_name));
        title.Reparent(desktop);

        // icons
        let icons = new inkVerticalPanel();
        icons.SetName(n"icons");
        icons.SetMargin(inkMargin(40.0, 100.0, 0.0, 0.0));
        icons.Reparent(desktop);
        this.AddButton(icons, n"icon_files", "[ FILES ]", n"OnFiles");
        this.AddButton(icons, n"icon_terminal", "[ TERMINAL ]", n"OnTerminal");
        this.AddButton(icons, n"icon_deck", "[ CYBERDECK ]", n"OnDeck");

        // taskbar
        let taskbar = new inkCanvas();
        taskbar.SetName(n"taskbar");
        taskbar.SetAnchor(inkEAnchor.BottomFillHorizontaly);
        taskbar.SetAnchorPoint(Vector2(0.5, 1.0));
        taskbar.SetSize(100.0, 60.0);
        taskbar.Reparent(desktop);
        RNRect(n"bg", RNColor(0.08, 0.02, 0.03, 0.95)).Reparent(taskbar);
        let exitButton = RNText(n"exit", 28, n"MainColors.Red");
        exitButton.SetMargin(inkMargin(30.0, 14.0, 0.0, 0.0));
        exitButton.SetText("EXIT DESKTOP");
        exitButton.SetInteractive(true);
        exitButton.Reparent(taskbar);
        exitButton.RegisterToCallback(n"OnRelease", this, n"OnExit");
        let clock = RNText(n"clock", 28, n"MainColors.Blue");
        clock.SetAnchor(inkEAnchor.TopRight);
        clock.SetAnchorPoint(Vector2(1.0, 0.0));
        clock.SetHAlign(inkEHorizontalAlign.Right);
        clock.SetMargin(inkMargin(0.0, 14.0, 30.0, 0.0));
        clock.Reparent(taskbar);
        this.m_clock = clock;

        // one window, reused by every app
        let window = new inkCanvas();
        window.SetName(n"window");
        window.SetAnchor(inkEAnchor.Fill);
        window.SetMargin(inkMargin(320.0, 90.0, 60.0, 100.0));
        window.SetVisible(false);
        window.Reparent(desktop);
        this.m_window = window;
        RNRect(n"bg", RNColor(0.04, 0.06, 0.09, 0.98)).Reparent(window);

        let body = new inkVerticalPanel();
        body.SetName(n"body");
        body.SetMargin(inkMargin(24.0, 16.0, 24.0, 16.0));
        body.Reparent(window);

        let bar = new inkHorizontalPanel();
        bar.SetName(n"titlebar");
        bar.Reparent(body);
        let windowTitle = RNText(n"title", 32, n"MainColors.Red");
        windowTitle.Reparent(bar);
        this.m_windowTitle = windowTitle;
        let close = RNText(n"close", 32, n"MainColors.Red");
        close.SetText("   [ X ]");
        close.SetInteractive(true);
        close.Reparent(bar);
        close.RegisterToCallback(n"OnRelease", this, n"OnCloseWindow");

        let header = RNText(n"header", 26, n"MainColors.Yellow");
        header.SetMargin(inkMargin(0.0, 10.0, 0.0, 6.0));
        header.SetInteractive(true);
        header.Reparent(body);
        header.RegisterToCallback(n"OnRelease", this, n"OnHeader");
        this.m_header = header;

        let i = 0;
        while i < this.VisibleRows() {
            let row = RNText(StringToName("row" + IntToString(i)), 26, n"MainColors.Blue");
            row.SetInteractive(true);
            row.SetWrappingAtPosition(1300.0);
            row.Reparent(body);
            row.RegisterToCallback(n"OnRelease", this, n"OnRow");
            ArrayPush(this.m_rows, row);
            i += 1;
        }

        let footerRow = new inkHorizontalPanel();
        footerRow.SetName(n"footerRow");
        footerRow.SetMargin(inkMargin(0.0, 10.0, 0.0, 0.0));
        footerRow.Reparent(body);
        let prevButton = RNText(n"prev", 26, n"MainColors.Yellow");
        prevButton.SetText("[ PREV ]   ");
        prevButton.SetInteractive(true);
        prevButton.Reparent(footerRow);
        prevButton.RegisterToCallback(n"OnRelease", this, n"OnPrev");
        let nextButton = RNText(n"next", 26, n"MainColors.Yellow");
        nextButton.SetText("[ NEXT ]   ");
        nextButton.SetInteractive(true);
        nextButton.Reparent(footerRow);
        nextButton.RegisterToCallback(n"OnRelease", this, n"OnNext");
        let footer = RNText(n"footer", 26, n"MainColors.Yellow");
        footer.Reparent(footerRow);
        this.m_footer = footer;
        this.m_pager = footerRow;

        // terminal input line
        let inputRow = new inkHorizontalPanel();
        inputRow.SetName(n"inputRow");
        inputRow.SetMargin(inkMargin(0.0, 10.0, 0.0, 0.0));
        inputRow.SetVisible(false);
        inputRow.Reparent(body);
        this.m_inputRow = inputRow;
        let prompt = RNText(n"prompt", 26, n"MainColors.Blue");
        prompt.SetMargin(inkMargin(0.0, 14.0, 12.0, 0.0));
        prompt.Reparent(inputRow);
        this.m_prompt = prompt;
        this.m_input = TextInput.Create();
        this.m_input.SetName(n"rn_command");
        this.m_input.SetMaxLength(200);
        this.m_input.SetWidth(900.0);
        this.m_input.Reparent(inputRow, controller);
        this.m_input.RegisterToCallback(n"OnInputKey", this, n"OnTerminalKey");
    }

    private func AddButton(parent: ref<inkCompoundWidget>, name: CName, label: String, callback: CName) {
        let button = RNText(name, 34, n"MainColors.Blue");
        button.SetMargin(inkMargin(0.0, 0.0, 0.0, 28.0));
        button.SetText(label);
        button.SetInteractive(true);
        button.Reparent(parent);
        button.RegisterToCallback(n"OnRelease", this, callback);
    }

    // --- drawing ----------------------------------------------------------------

    private func UpdateClock() {
        let controller = this.m_controller;
        if !IsDefined(controller) || !IsDefined(this.m_clock) {
            return;
        }
        let player = controller.GetPlayerControlledObject();
        if !IsDefined(player) {
            return;
        }
        let time = GameInstance.GetTimeSystem(player.GetGame()).GetGameTime();
        let minutes = GameTime.Minutes(time);
        this.m_clock.SetText(IntToString(GameTime.Hours(time)) + ":" + (minutes < 10 ? "0" : "") + IntToString(minutes));
    }

    private func SetRow(i: Int32, text: String, color: CName) {
        let row = this.m_rows[i];
        row.SetText(StrLen(text) > 0 ? text : " ");
        row.BindProperty(n"tintColor", color);
    }

    private func ShowWindow(title: String) {
        this.m_window.SetVisible(true);
        this.m_windowTitle.SetText(title);
        this.m_inputRow.SetVisible(this.m_mode == 3);
        this.UpdateClock();
    }

    private func DrawFiles() {
        this.ListCurrentFolder();
        let total = ArraySize(this.m_listNames);
        this.m_offset = Clamp(this.m_offset, 0, Max(0, total - this.VisibleRows()));
        this.ShowWindow("FILES");
        this.m_header.SetText(StrLen(this.m_cwd) > 0 ? "/" + this.m_cwd + "    [ UP ]" : "/");

        let i = 0;
        while i < this.VisibleRows() {
            let index = this.m_offset + i;
            if index < total {
                if this.m_listIsDir[index] {
                    this.SetRow(i, "[DIR]  " + this.m_listNames[index], n"MainColors.Yellow");
                } else {
                    let locked = this.m_locked[this.m_listIndex[index]];
                    this.SetRow(i, (locked ? "[LOCKED]  " : "         ") + this.m_listNames[index],
                        locked ? n"MainColors.Red" : n"MainColors.Blue");
                }
            } else {
                this.SetRow(i, "", n"MainColors.Blue");
            }
            i += 1;
        }

        this.m_pager.SetVisible(true);
        this.m_footer.SetText(total > this.VisibleRows()
            ? IntToString(this.m_offset + 1) + "-" + IntToString(Min(total, this.m_offset + this.VisibleRows())) + " of " + IntToString(total)
            : IntToString(total) + " items");
    }

    private func DrawDocument() {
        let path = this.m_paths[this.m_docIndex];
        this.ShowWindow(StrUpper(StrAfterLast(path, "/")));
        this.m_header.SetText("/" + path + "    [ BACK ]");

        let text = this.m_locked[this.m_docIndex]
            ? "ENCRYPTED. Breach this computer from the Terminal to read it."
            : this.m_texts[this.m_docIndex];
        let pages = Max(1, (StrLen(text) + this.PageChars() - 1) / this.PageChars());
        this.m_docPage = Clamp(this.m_docPage, 0, pages - 1);
        let page = StrMid(text, this.m_docPage * this.PageChars(), this.PageChars());

        // the page text goes in the first row, which wraps; the other rows stay empty
        this.SetRow(0, page, n"MainColors.Blue");
        let i = 1;
        while i < this.VisibleRows() {
            this.SetRow(i, "", n"MainColors.Blue");
            i += 1;
        }
        this.m_pager.SetVisible(true);
        this.m_footer.SetText("page " + IntToString(this.m_docPage + 1) + " of " + IntToString(pages));
    }

    private func DrawTerminal() {
        let service = DeckService.Get();
        this.ShowWindow("TERMINAL");
        this.m_header.SetText("Type a command and press Enter, or click [ CYBERDECK ] to use the full deck.");
        if !IsDefined(service) {
            this.SetRow(0, "Cyberdeck service not running.", n"MainColors.Red");
            return;
        }
        let total = service.GetLineCount();
        let first = Max(0, total - this.VisibleRows());
        let i = 0;
        while i < this.VisibleRows() {
            let index = first + i;
            if index < total {
                this.SetRow(i, service.GetLine(index), this.ColorFor(service.GetKind(index)));
            } else {
                this.SetRow(i, "", n"MainColors.Blue");
            }
            i += 1;
        }
        this.m_prompt.SetText(service.GetPrompt());
        this.m_pager.SetVisible(false);
    }

    private func ColorFor(kind: Int32) -> CName {
        switch kind {
            case 2: return n"MainColors.Green";
            case 3: return n"MainColors.Yellow";
            case 4: return n"MainColors.Red";
            default: return n"MainColors.Blue";
        }
    }

    private func Redraw() {
        switch this.m_mode {
            case 1: this.DrawFiles(); break;
            case 2: this.DrawDocument(); break;
            case 3: this.DrawTerminal(); break;
            default: break;
        }
    }

    // --- called by DeckService --------------------------------------------------

    public func OnDeckChanged() {
        if this.m_mode == 3 && IsDefined(this.m_desktop) {
            this.DrawTerminal();
        }
    }

    public func OnFilesChanged(key: String) {
        if Equals(key, this.m_key) && IsDefined(this.m_desktop) {
            this.ReloadGeneratedFiles();
            if this.m_mode == 1 {
                this.DrawFiles();
            }
        }
    }

    // --- clicks -----------------------------------------------------------------

    protected cb func OnLaunch(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") {
            this.ReloadGeneratedFiles();
            this.m_desktop.SetVisible(true);
            this.UpdateClock();
        }
        return false;
    }

    protected cb func OnExit(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") {
            this.m_mode = 0;
            this.m_window.SetVisible(false);
            this.m_desktop.SetVisible(false);
        }
        return false;
    }

    protected cb func OnFiles(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") {
            this.m_mode = 1;
            this.m_offset = 0;
            this.DrawFiles();
        }
        return false;
    }

    // Connects the deck to this computer, once Lua has registered it.
    private func ConnectDeck(service: ref<DeckService>) {
        if this.m_terminalConnected {
            return;
        }
        let addr = service.GetMachineAddr(this.m_key);
        if StrLen(addr) > 0 {
            this.m_terminalConnected = true;
            service.Submit("connect " + addr);
        } else {
            service.RequestMachine(this.m_key, this.m_name);
        }
    }

    protected cb func OnTerminal(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") {
            this.m_mode = 3;
            let service = DeckService.Get();
            if IsDefined(service) {
                this.ConnectDeck(service);
            }
            this.DrawTerminal();
            if IsDefined(this.m_controller) {
                this.m_controller.RequestSetFocus(this.m_input.GetRootWidget());
            }
        }
        return false;
    }

    protected cb func OnDeck(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") {
            let service = DeckService.Get();
            if IsDefined(service) {
                this.ConnectDeck(service);
                service.Open();
            }
        }
        return false;
    }

    protected cb func OnCloseWindow(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") {
            this.m_mode = 0;
            this.m_window.SetVisible(false);
        }
        return false;
    }

    // folder path: go up a level; document: back to its folder
    protected cb func OnHeader(e: ref<inkPointerEvent>) -> Bool {
        if !e.IsAction(n"click") {
            return false;
        }
        if this.m_mode == 2 {
            this.m_mode = 1;
            this.DrawFiles();
        } else {
            if this.m_mode == 1 && StrLen(this.m_cwd) > 0 {
                this.m_cwd = StrFindFirst(this.m_cwd, "/") >= 0 ? StrBeforeLast(this.m_cwd, "/") : "";
                this.m_offset = 0;
                this.DrawFiles();
            }
        }
        return false;
    }

    protected cb func OnRow(e: ref<inkPointerEvent>) -> Bool {
        if !e.IsAction(n"click") || this.m_mode != 1 {
            return false;
        }
        let name = NameToString(e.GetCurrentTarget().GetName());
        let row = StringToInt(StrAfterFirst(name, "row"), -1);
        let index = this.m_offset + row;
        if row < 0 || index >= ArraySize(this.m_listNames) {
            return false;
        }
        if this.m_listIsDir[index] {
            this.m_cwd = StrLen(this.m_cwd) > 0 ? this.m_cwd + "/" + this.m_listNames[index] : this.m_listNames[index];
            this.m_offset = 0;
            this.DrawFiles();
        } else {
            this.m_docIndex = this.m_listIndex[index];
            this.m_docPage = 0;
            this.m_mode = 2;
            this.DrawDocument();
        }
        return false;
    }

    protected cb func OnPrev(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") {
            this.Page(-1);
        }
        return false;
    }

    protected cb func OnNext(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") {
            this.Page(1);
        }
        return false;
    }

    private func Page(step: Int32) {
        if this.m_mode == 1 {
            this.m_offset += step * this.VisibleRows();
            this.DrawFiles();
        } else {
            if this.m_mode == 2 {
                this.m_docPage += step;
                this.DrawDocument();
            }
        }
    }

    protected cb func OnTerminalKey(event: ref<inkKeyInputEvent>) -> Bool {
        if Equals(event.GetAction(), EInputAction.IACT_Press) && Equals(event.GetKey(), EInputKey.IK_Enter) {
            let service = DeckService.Get();
            if IsDefined(service) {
                service.Submit(this.m_input.GetText());
            }
            this.m_input.SetText("");
        }
        return false;
    }
}

// --- hooking into computer screens -------------------------------------------

@addField(ComputerInkGameController)
private let m_rnDesktop: ref<RNDesktop>;

@wrapMethod(ComputerInkGameController)
protected cb func OnMainLayoutSpawned(widget: ref<inkWidget>, userData: ref<IScriptable>) -> Bool {
    let result = wrappedMethod(widget, userData);

    if !IsDefined(this.m_rnDesktop) {
        let owner = this.GetOwner();
        let root = this.GetRootWidget() as inkCompoundWidget;
        if IsDefined(owner) && IsDefined(root) {
            let ps = owner.GetDevicePS();
            let key = EntityID.ToDebugString(owner.GetEntityID());
            this.m_rnDesktop = RNDesktop.Create(this, root, key, ps.GetDeviceName(), ps);
        }
    }

    return result;
}
