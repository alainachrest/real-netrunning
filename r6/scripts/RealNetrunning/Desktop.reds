// -----------------------------------------------------------------------------
// Real Netrunning - simulated computer desktops
// -----------------------------------------------------------------------------
//
// Adds a DESKTOP button to every in-game computer screen. It switches into a
// simulated OS drawn over the vanilla screen, which stays underneath untouched.
//
//   Desktop   icon tiles, a taskbar with a start menu, a button per open window,
//             and a tray with NetWatch heat and the clock
//   Windows   draggable by the title bar, minimise and close, click to bring
//             to front; several can be open at once
//   Apps      Files (the computer's mail and documents, generated system files,
//             and on V's own computers the files you saved), document viewer,
//             Terminal (the deck shell, connected to this computer), Cyberdeck
//
// Generated and saved files come from the Lua mod through DeckService (Deck.reds).

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

// A clickable text label.
func RNButton(name: CName, label: String, size: Int32, color: CName) -> ref<inkText> {
    let button = RNText(name, size, color);
    button.SetText(label);
    button.SetInteractive(true);
    return button;
}

func RNShapes() -> ResRef {
    return r"base\\gameplay\\gui\\common\\shapes\\atlas_shapes_sync.inkatlas";
}

func RNHubIcons() -> ResRef {
    return r"base\\gameplay\\gui\\fullscreen\\hub_menu\\hub_atlas.inkatlas";
}

// A themed image from one of the game's atlases, stretched to fill its parent.
func RNImage(name: CName, atlas: ResRef, part: CName, color: CName, opacity: Float) -> ref<inkImage> {
    let image = new inkImage();
    image.SetName(name);
    image.SetAtlasResource(atlas);
    image.SetTexturePart(part);
    image.SetNineSliceScale(true);
    image.SetAnchor(inkEAnchor.Fill);
    image.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
    image.BindProperty(n"tintColor", color);
    image.SetOpacity(opacity);
    return image;
}

// A hub-menu icon of a fixed size.
func RNIcon(name: CName, part: CName, size: Float, color: CName) -> ref<inkImage> {
    let icon = new inkImage();
    icon.SetName(name);
    icon.SetAtlasResource(RNHubIcons());
    icon.SetTexturePart(part);
    icon.SetSize(size, size);
    icon.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
    icon.BindProperty(n"tintColor", color);
    return icon;
}

// Which icon each app uses.
func RNAppIcon(app: CName) -> CName {
    if Equals(app, n"app_files") { return n"ico_data"; }
    if Equals(app, n"app_mail") { return n"ico_phone"; }
    if Equals(app, n"app_documents") { return n"ico_shards_hub"; }
    if Equals(app, n"app_system") { return n"ico_stats_hub"; }
    if Equals(app, n"app_browser") { return n"ico_map"; }
    if Equals(app, n"app_market") { return n"ico_inventory"; }
    if Equals(app, n"app_terminal") { return n"ico_deck_hub"; }
    if Equals(app, n"app_deck") { return n"ico_cyberware"; }
    if Equals(app, n"app_exit") { return n"ico_save"; }
    return n"ico_journal";
}

func RNShorten(text: String, length: Int32) -> String {
    if StrLen(text) <= length {
        return text;
    }
    return StrLeft(text, length - 2) + "..";
}

// Brightens widgets under the mouse.
public class RNHover {
    public func Attach(widget: ref<inkWidget>) {
        widget.SetOpacity(0.8);
        widget.RegisterToCallback(n"OnHoverOver", this, n"OnHoverIn");
        widget.RegisterToCallback(n"OnHoverOut", this, n"OnHoverOff");
    }

    protected cb func OnHoverIn(e: ref<inkPointerEvent>) -> Bool {
        e.GetCurrentTarget().SetOpacity(1.0);
        return false;
    }

    protected cb func OnHoverOff(e: ref<inkPointerEvent>) -> Bool {
        e.GetCurrentTarget().SetOpacity(0.8);
        return false;
    }
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

// The number at the end of a widget name like "task12" -> 12.
func RNNameNumber(name: CName, prefix: String) -> Int32 {
    return StringToInt(StrAfterFirst(NameToString(name), prefix), -1);
}

// --- a window -------------------------------------------------------------------

public class RNWindow {
    public let m_id: Int32;
    public let m_kind: Int32;          // 1 files, 2 document, 3 terminal, 4 browser
    public let m_title: String;
    public let m_minimized: Bool;
    public let m_root: wref<inkCanvas>;

    private let m_desktop: wref<RNDesktop>;
    private let m_frame: wref<inkImage>;
    private let m_titleText: wref<inkText>;
    private let m_header: wref<inkText>;
    private let m_rows: array<wref<inkText>>;
    private let m_pager: wref<inkHorizontalPanel>;
    private let m_footer: wref<inkText>;
    private let m_save: wref<inkText>;
    private let m_inputRow: wref<inkHorizontalPanel>;
    private let m_prompt: wref<inkText>;
    private let m_input: ref<TextInput>;

    // files
    private let m_cwd: String;
    private let m_listNames: array<String>;
    private let m_listIsDir: array<Bool>;
    private let m_listIndex: array<Int32>;
    private let m_offset: Int32;

    // document
    public let m_docIndex: Int32;
    private let m_docPage: Int32;

    // browser (kind 4) draws through its own view, see Browser.reds
    private let m_browser: ref<RNBrowserView>;

    private func VisibleRows() -> Int32 { return 12; }
    private func PageChars() -> Int32 { return 900; }

    public static func Create(desktop: ref<RNDesktop>, id: Int32, kind: Int32, title: String,
                              layer: ref<inkCompoundWidget>, controller: ref<inkGameController>,
                              x: Float, y: Float) -> ref<RNWindow> {
        let self = new RNWindow();
        self.m_desktop = desktop;
        self.m_id = id;
        self.m_kind = kind;
        self.m_title = title;
        self.m_cwd = "";
        self.Build(layer, controller, x, y);
        return self;
    }

    private func Build(layer: ref<inkCompoundWidget>, controller: ref<inkGameController>, x: Float, y: Float) {
        let root = new inkCanvas();
        root.SetName(StringToName("window" + IntToString(this.m_id)));
        root.SetAnchor(inkEAnchor.TopLeft);
        root.SetSize(this.m_kind == 4 ? Vector2(1320.0, 780.0) : Vector2(1100.0, 640.0));
        root.SetTranslation(x, y);
        root.SetInteractive(true);
        root.Reparent(layer);
        root.RegisterToCallback(n"OnPress", this, n"OnWindowPress");
        this.m_root = root;

        RNImage(n"bg", RNShapes(), n"cell_bg", n"MainColors.Fullscreen_PrimaryBackgroundDarkest", 0.97).Reparent(root);
        let frame = RNImage(n"frame", RNShapes(), n"cell_fg", n"MainColors.Red", 1.0);
        frame.Reparent(root);
        this.m_frame = frame;

        // title bar: drag handle, title, minimise and close
        let bar = new inkCanvas();
        bar.SetName(n"titlebar");
        bar.SetAnchor(inkEAnchor.TopFillHorizontaly);
        bar.SetSize(100.0, 52.0);
        bar.SetInteractive(true);
        bar.Reparent(root);
        bar.RegisterToCallback(n"OnPress", this, n"OnTitlePress");
        let barBg = RNImage(n"bg", RNShapes(), n"button_big2_bg", n"MainColors.PanelDarkRed", 0.85);
        barBg.SetMargin(inkMargin(4.0, 4.0, 4.0, 0.0));
        barBg.Reparent(bar);

        let titleText = RNText(n"title", 28, n"MainColors.Red");
        titleText.SetMargin(inkMargin(18.0, 10.0, 0.0, 0.0));
        titleText.SetText(this.m_title);
        titleText.Reparent(bar);
        this.m_titleText = titleText;

        let buttons = new inkHorizontalPanel();
        buttons.SetName(n"buttons");
        buttons.SetAnchor(inkEAnchor.TopRight);
        buttons.SetAnchorPoint(Vector2(1.0, 0.0));
        buttons.SetMargin(inkMargin(0.0, 10.0, 18.0, 0.0));
        buttons.Reparent(bar);
        let minimize = RNButton(n"minimize", "[ _ ]   ", 28, n"MainColors.Blue");
        minimize.Reparent(buttons);
        this.Hover(minimize);
        minimize.RegisterToCallback(n"OnRelease", this, n"OnMinimize");
        let close = RNButton(n"close", "[ X ]", 28, n"MainColors.Red");
        close.Reparent(buttons);
        this.Hover(close);
        close.RegisterToCallback(n"OnRelease", this, n"OnClose");

        if this.m_kind == 4 {
            this.m_browser = RNBrowserView.Create(this.m_desktop, root, controller);
            return;
        }

        // body
        let body = new inkVerticalPanel();
        body.SetName(n"body");
        body.SetMargin(inkMargin(22.0, 66.0, 22.0, 16.0));
        body.Reparent(root);

        let header = RNButton(n"header", " ", 24, n"MainColors.Yellow");
        header.SetMargin(inkMargin(0.0, 0.0, 0.0, 8.0));
        header.Reparent(body);
        header.RegisterToCallback(n"OnRelease", this, n"OnHeader");
        this.m_header = header;

        let i = 0;
        while i < this.VisibleRows() {
            let row = RNButton(StringToName("row" + IntToString(i)), " ", 25, n"MainColors.Blue");
            row.SetWrappingAtPosition(1040.0);
            row.Reparent(body);
            row.RegisterToCallback(n"OnRelease", this, n"OnRow");
            ArrayPush(this.m_rows, row);
            i += 1;
        }

        let pager = new inkHorizontalPanel();
        pager.SetName(n"pager");
        pager.SetMargin(inkMargin(0.0, 8.0, 0.0, 0.0));
        pager.Reparent(body);
        this.m_pager = pager;
        let prevButton = RNButton(n"prev", "[ PREV ]   ", 24, n"MainColors.Yellow");
        prevButton.Reparent(pager);
        this.Hover(prevButton);
        prevButton.RegisterToCallback(n"OnRelease", this, n"OnPrev");
        let nextButton = RNButton(n"next", "[ NEXT ]   ", 24, n"MainColors.Yellow");
        nextButton.Reparent(pager);
        this.Hover(nextButton);
        nextButton.RegisterToCallback(n"OnRelease", this, n"OnNext");
        let footer = RNText(n"footer", 24, n"MainColors.Yellow");
        footer.Reparent(pager);
        this.m_footer = footer;
        let save = RNButton(n"save", "      [ SAVE TO HOME ]", 24, n"MainColors.Green");
        save.SetVisible(false);
        save.Reparent(pager);
        this.Hover(save);
        save.RegisterToCallback(n"OnRelease", this, n"OnSave");
        this.m_save = save;

        // terminal input line
        let inputRow = new inkHorizontalPanel();
        inputRow.SetName(n"inputRow");
        inputRow.SetMargin(inkMargin(0.0, 8.0, 0.0, 0.0));
        inputRow.SetVisible(this.m_kind == 3);
        inputRow.Reparent(body);
        this.m_inputRow = inputRow;
        let prompt = RNText(n"prompt", 25, n"MainColors.Blue");
        prompt.SetMargin(inkMargin(0.0, 14.0, 12.0, 0.0));
        prompt.Reparent(inputRow);
        this.m_prompt = prompt;
        if this.m_kind == 3 {
            this.m_input = TextInput.Create();
            this.m_input.SetName(n"rn_command");
            this.m_input.SetMaxLength(200);
            this.m_input.SetWidth(820.0);
            this.m_input.Reparent(inputRow, controller);
            this.m_input.RegisterToCallback(n"OnInputKey", this, n"OnTerminalKey");
        }
    }

    private func Hover(widget: ref<inkWidget>) {
        if IsDefined(this.m_desktop) {
            this.m_desktop.Hover(widget);
        }
    }

    public func SetFocused(focused: Bool) {
        if IsDefined(this.m_frame) {
            this.m_frame.SetOpacity(focused ? 1.0 : 0.35);
        }
    }

    public func GetInputWidget() -> wref<inkWidget> {
        if IsDefined(this.m_input) {
            return this.m_input.GetRootWidget();
        }
        return null;
    }

    public func SetMinimized(minimized: Bool) {
        this.m_minimized = minimized;
        this.m_root.SetVisible(!minimized);
    }

    public func Destroy(layer: ref<inkCompoundWidget>) {
        if IsDefined(this.m_root) {
            layer.RemoveChild(this.m_root);
        }
    }

    // --- drawing --------------------------------------------------------------

    private func SetRow(i: Int32, text: String, color: CName) {
        let row = this.m_rows[i];
        row.SetText(StrLen(text) > 0 ? text : " ");
        row.BindProperty(n"tintColor", color);
    }

    private func ClearRowsFrom(first: Int32) {
        let i = first;
        while i < this.VisibleRows() {
            this.SetRow(i, "", n"MainColors.Blue");
            i += 1;
        }
    }

    public func Draw() {
        let desktop = this.m_desktop;
        if !IsDefined(desktop) || !IsDefined(this.m_root) {
            return;
        }
        switch this.m_kind {
            case 1: this.DrawFiles(desktop); break;
            case 2: this.DrawDocument(desktop); break;
            case 3: this.DrawTerminal(); break;
            case 4: break;
            default: break;
        }
    }

    public func OpenFolder(path: String) {
        this.m_cwd = path;
        this.m_offset = 0;
    }

    private func ListCurrentFolder(desktop: ref<RNDesktop>) {
        ArrayClear(this.m_listNames);
        ArrayClear(this.m_listIsDir);
        ArrayClear(this.m_listIndex);

        let prefix = StrLen(this.m_cwd) > 0 ? this.m_cwd + "/" : "";
        let i = 0;
        let count = desktop.GetFileCount();
        while i < count {
            let path = desktop.GetFilePath(i);
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

    private func DrawFiles(desktop: ref<RNDesktop>) {
        this.ListCurrentFolder(desktop);
        let total = ArraySize(this.m_listNames);
        this.m_offset = Clamp(this.m_offset, 0, Max(0, total - this.VisibleRows()));
        this.m_header.SetText(StrLen(this.m_cwd) > 0 ? "[ < UP ]   /" + this.m_cwd : "/");

        let i = 0;
        while i < this.VisibleRows() {
            let index = this.m_offset + i;
            if index < total {
                if this.m_listIsDir[index] {
                    this.SetRow(i, "[DIR]     " + this.m_listNames[index], n"MainColors.Yellow");
                } else {
                    let locked = desktop.IsFileLocked(this.m_listIndex[index]);
                    this.SetRow(i, (locked ? "[LOCK]    " : "[FILE]    ") + this.m_listNames[index],
                        locked ? n"MainColors.Red" : n"MainColors.Blue");
                }
            } else {
                this.SetRow(i, "", n"MainColors.Blue");
            }
            i += 1;
        }

        this.m_pager.SetVisible(true);
        this.m_save.SetVisible(false);
        this.m_footer.SetText(total > this.VisibleRows()
            ? IntToString(this.m_offset + 1) + "-" + IntToString(Min(total, this.m_offset + this.VisibleRows())) + " of " + IntToString(total)
            : IntToString(total) + " items");
    }

    private func DrawDocument(desktop: ref<RNDesktop>) {
        let locked = desktop.IsFileLocked(this.m_docIndex);
        let text = locked
            ? "ENCRYPTED. Breach this computer from the Terminal to read it."
            : desktop.GetFileText(this.m_docIndex);
        let pages = Max(1, (StrLen(text) + this.PageChars() - 1) / this.PageChars());
        this.m_docPage = Clamp(this.m_docPage, 0, pages - 1);

        this.m_header.SetText("/" + desktop.GetFilePath(this.m_docIndex));
        // the page goes in the first row, which wraps
        this.SetRow(0, StrMid(text, this.m_docPage * this.PageChars(), this.PageChars()), n"MainColors.Blue");
        this.ClearRowsFrom(1);

        this.m_pager.SetVisible(true);
        this.m_footer.SetText("page " + IntToString(this.m_docPage + 1) + " of " + IntToString(pages));
        this.m_save.SetVisible(!locked && !desktop.IsHomeMachine());
    }

    private func DrawTerminal() {
        let service = DeckService.Get();
        this.m_header.SetText("Type a command and press Enter.");
        this.m_pager.SetVisible(false);
        if !IsDefined(service) {
            this.SetRow(0, "Cyberdeck service not running.", n"MainColors.Red");
            this.ClearRowsFrom(1);
            return;
        }
        let total = service.GetLineCount();
        let first = Max(0, total - this.VisibleRows());
        let i = 0;
        while i < this.VisibleRows() {
            let index = first + i;
            if index < total {
                this.SetRow(i, service.GetLine(index), RNDesktop.ColorFor(service.GetKind(index)));
            } else {
                this.SetRow(i, "", n"MainColors.Blue");
            }
            i += 1;
        }
        this.m_prompt.SetText(service.GetPrompt());
    }

    // --- browser --------------------------------------------------------------

    public func Navigate(url: String, remember: Bool) {
        if IsDefined(this.m_browser) {
            this.m_browser.Navigate(url, remember);
        }
    }

    public func OnPageReady(url: String) {
        if IsDefined(this.m_browser) && this.m_browser.OnPageReady(url) {
            this.m_title = this.m_browser.GetTitle();
            this.m_titleText.SetText(StrUpper(RNShorten(this.m_title, 40)));
            if IsDefined(this.m_desktop) {
                this.m_desktop.RefreshTaskbarTitles();
            }
        }
    }

    public func GetBrowser() -> ref<RNBrowserView> {
        return this.m_browser;
    }

    // --- input ----------------------------------------------------------------

    protected cb func OnWindowPress(e: ref<inkPointerEvent>) -> Bool {
        if IsDefined(this.m_desktop) {
            this.m_desktop.Focus(this);
        }
        return false;
    }

    protected cb func OnTitlePress(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"mouse_left") && IsDefined(this.m_desktop) {
            this.m_desktop.BeginDrag(this, e.GetScreenSpacePosition());
        }
        return false;
    }

    protected cb func OnMinimize(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") && IsDefined(this.m_desktop) {
            this.m_desktop.Minimize(this);
        }
        return false;
    }

    protected cb func OnClose(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") && IsDefined(this.m_desktop) {
            this.m_desktop.CloseWindow(this);
        }
        return false;
    }

    // files: go up a folder
    protected cb func OnHeader(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") && this.m_kind == 1 && StrLen(this.m_cwd) > 0 {
            this.m_cwd = StrFindFirst(this.m_cwd, "/") >= 0 ? StrBeforeLast(this.m_cwd, "/") : "";
            this.m_offset = 0;
            this.Draw();
        }
        return false;
    }

    protected cb func OnRow(e: ref<inkPointerEvent>) -> Bool {
        if !e.IsAction(n"click") || !IsDefined(this.m_desktop) {
            return false;
        }
        let row = RNNameNumber(e.GetCurrentTarget().GetName(), "row");
        if this.m_kind != 1 {
            return false;
        }
        let index = this.m_offset + row;
        if row < 0 || index >= ArraySize(this.m_listNames) {
            return false;
        }
        if this.m_listIsDir[index] {
            this.m_cwd = StrLen(this.m_cwd) > 0 ? this.m_cwd + "/" + this.m_listNames[index] : this.m_listNames[index];
            this.m_offset = 0;
            this.Draw();
        } else {
            this.m_desktop.OpenDocument(this.m_listIndex[index]);
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
        if this.m_kind == 1 {
            this.m_offset += step * this.VisibleRows();
        } else {
            this.m_docPage += step;
        }
        this.Draw();
    }

    protected cb func OnSave(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") && this.m_kind == 2 && IsDefined(this.m_desktop) {
            this.m_desktop.SaveToHome(this.m_docIndex);
            this.m_footer.SetText("Saved to your home computer.");
        }
        return false;
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

// --- the desktop ------------------------------------------------------------------

public class RNDesktop {
    // which computer this is
    private let m_controller: wref<ComputerInkGameController>;
    private let m_key: String;
    private let m_name: String;
    private let m_isHome: Bool;

    // everything the Files app shows: vanilla docs, then generated, then saved files
    private let m_paths: array<String>;
    private let m_texts: array<String>;
    private let m_locked: array<Bool>;
    private let m_vanillaCount: Int32;

    // widgets
    private let m_desktop: wref<inkCanvas>;
    private let m_windowsLayer: wref<inkCanvas>;
    private let m_startMenu: wref<inkCanvas>;
    private let m_taskButtons: wref<inkHorizontalPanel>;
    private let m_heat: wref<inkText>;
    private let m_clock: wref<inkText>;

    // windows
    private let m_hover: ref<RNHover>;
    private let m_windows: array<ref<RNWindow>>;
    private let m_nextId: Int32;
    private let m_focusedId: Int32;
    private let m_dragging: wref<RNWindow>;
    private let m_grab: Vector2;
    private let m_terminalConnected: Bool;

    public static func Create(controller: ref<ComputerInkGameController>, root: ref<inkCompoundWidget>,
                              key: String, name: String, ps: ref<ComputerControllerPS>) -> ref<RNDesktop> {
        let self = new RNDesktop();
        self.m_controller = controller;
        self.m_key = key;
        self.m_name = RNLocalize(name);
        self.m_hover = new RNHover();
        self.LoadVanillaDocuments(ps);
        self.Build(root);

        controller.RegisterToGlobalInputCallback(n"OnPostOnRelative", self, n"OnMouseMove");
        controller.RegisterToGlobalInputCallback(n"OnPostOnRelease", self, n"OnMouseUp");

        let service = DeckService.Get();
        if IsDefined(service) {
            service.RegisterTerminal(self);
            service.RequestMachine(key, self.m_name);
        }
        return self;
    }

    public func Hover(widget: ref<inkWidget>) {
        this.m_hover.Attach(widget);
    }

    public static func ColorFor(kind: Int32) -> CName {
        switch kind {
            case 2: return n"MainColors.Green";
            case 3: return n"MainColors.Yellow";
            case 4: return n"MainColors.Red";
            default: return n"MainColors.Blue";
        }
    }

    // --- files ----------------------------------------------------------------

    public func GetFileCount() -> Int32 { return ArraySize(this.m_paths); }
    public func GetFilePath(index: Int32) -> String { return this.m_paths[index]; }
    public func GetFileText(index: Int32) -> String { return this.m_texts[index]; }
    public func IsFileLocked(index: Int32) -> Bool { return this.m_locked[index]; }
    public func IsHomeMachine() -> Bool { return this.m_isHome; }

    private func LoadVanillaDocuments(ps: ref<ComputerControllerPS>) {
        if !IsDefined(ps) {
            return;
        }
        for thumb in ps.GetMailThumbnailWidgets() {
            this.AddDocument("Mail", thumb.folderName, ps.GetMailWidget(thumb.documentAdress));
        }
        for thumb in ps.GetFileThumbnailWidgets() {
            this.AddDocument("Documents", thumb.folderName, ps.GetFileWidget(thumb.documentAdress));
        }
        this.m_vanillaCount = ArraySize(this.m_paths);
    }

    private func AddDocument(root: String, folder: String, doc: SDocumentWidgetPackage) {
        let folderName = StrLen(folder) > 0 ? RNSafeName(folder) : "Inbox";
        let body = "";
        if StrLen(doc.owner) > 0 {
            body = "From: " + RNLocalize(doc.owner) + "\n";
        }
        if StrLen(doc.date) > 0 {
            body += RNLocalize(doc.date) + "\n";
        }
        body += "\n" + RNLocalize(doc.content);
        ArrayPush(this.m_paths, root + "/" + folderName + "/" + RNSafeName(doc.title));
        ArrayPush(this.m_texts, body);
        ArrayPush(this.m_locked, doc.isEncrypted);
    }

    private func ReloadFiles() {
        ArrayResize(this.m_paths, this.m_vanillaCount);
        ArrayResize(this.m_texts, this.m_vanillaCount);
        ArrayResize(this.m_locked, this.m_vanillaCount);
        let service = DeckService.Get();
        if !IsDefined(service) {
            return;
        }
        this.m_isHome = StrBeginsWith(service.GetMachineAddr(this.m_key), "home.");
        for entry in service.GetMachineFiles(this.m_key) {
            ArrayPush(this.m_paths, "System" + entry.path);
            ArrayPush(this.m_texts, entry.text);
            ArrayPush(this.m_locked, entry.locked);
        }
        if this.m_isHome {
            let i = 0;
            while i < service.GetHomeFileCount() {
                ArrayPush(this.m_paths, "Home/Saved/" + service.GetHomeFileName(i));
                ArrayPush(this.m_texts, service.GetHomeFileText(i));
                ArrayPush(this.m_locked, false);
                i += 1;
            }
        }
    }

    public func SaveToHome(index: Int32) {
        let service = DeckService.Get();
        if IsDefined(service) && index >= 0 && index < ArraySize(this.m_paths) {
            service.RequestSaveToHome(StrUpper(this.m_name) + " - " + StrAfterLast(this.m_paths[index], "/"), this.m_texts[index]);
        }
    }

    // --- building -------------------------------------------------------------

    private func Build(root: ref<inkCompoundWidget>) {
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

        let desktop = new inkCanvas();
        desktop.SetName(n"rn_desktop");
        desktop.SetAnchor(inkEAnchor.Fill);
        desktop.SetInteractive(true);
        desktop.SetVisible(false);
        desktop.Reparent(root);
        this.m_desktop = desktop;
        RNRect(n"wallpaper", RNColor(0.015, 0.02, 0.035, 0.98)).Reparent(desktop);
        let vignette = new inkImage();
        vignette.SetName(n"vignette");
        vignette.SetAtlasResource(r"base\\gameplay\\gui\\widgets\\notifications\\vignette.inkatlas");
        vignette.SetTexturePart(n"vignette_1");
        vignette.SetNineSliceScale(true);
        vignette.SetAnchor(inkEAnchor.Fill);
        vignette.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
        vignette.BindProperty(n"tintColor", n"MainColors.Red");
        vignette.SetOpacity(0.35);
        vignette.Reparent(desktop);

        let brand = RNText(n"brand", 120, n"MainColors.Red");
        brand.SetAnchor(inkEAnchor.BottomRight);
        brand.SetAnchorPoint(Vector2(1.0, 1.0));
        brand.SetHAlign(inkEHorizontalAlign.Right);
        brand.SetMargin(inkMargin(0.0, 0.0, 60.0, 110.0));
        brand.SetOpacity(0.12);
        brand.SetText("NC//OS");
        brand.Reparent(desktop);
        let watermark = RNText(n"watermark", 30, n"MainColors.Red");
        watermark.SetAnchor(inkEAnchor.BottomRight);
        watermark.SetAnchorPoint(Vector2(1.0, 1.0));
        watermark.SetHAlign(inkEHorizontalAlign.Right);
        watermark.SetMargin(inkMargin(0.0, 0.0, 66.0, 90.0));
        watermark.SetOpacity(0.4);
        watermark.SetText(StrUpper(this.m_name));
        watermark.Reparent(desktop);

        // icon tiles, two columns
        let icons = new inkHorizontalPanel();
        icons.SetName(n"icons");
        icons.SetMargin(inkMargin(40.0, 40.0, 0.0, 0.0));
        icons.Reparent(desktop);
        let colA = new inkVerticalPanel();
        colA.SetName(n"colA");
        colA.Reparent(icons);
        let colB = new inkVerticalPanel();
        colB.SetName(n"colB");
        colB.SetMargin(inkMargin(20.0, 0.0, 0.0, 0.0));
        colB.Reparent(icons);
        this.AddIcon(colA, n"app_files", "Files");
        this.AddIcon(colA, n"app_mail", "Mail");
        this.AddIcon(colA, n"app_browser", "Browser");
        this.AddIcon(colA, n"app_market", "Exchange");
        this.AddIcon(colB, n"app_terminal", "Terminal");
        this.AddIcon(colB, n"app_deck", "Cyberdeck");
        this.AddIcon(colB, n"app_system", "System");

        // windows sit above the icons and below the taskbar and start menu
        let windows = new inkCanvas();
        windows.SetName(n"windows");
        windows.SetAnchor(inkEAnchor.Fill);
        windows.Reparent(desktop);
        this.m_windowsLayer = windows;

        this.BuildTaskbar(desktop);
        this.BuildStartMenu(desktop);
    }

    private func AddIcon(parent: ref<inkCompoundWidget>, name: CName, label: String) {
        let tile = new inkCanvas();
        tile.SetName(name);
        tile.SetSize(150.0, 150.0);
        tile.SetMargin(inkMargin(0.0, 0.0, 0.0, 16.0));
        tile.SetInteractive(true);
        tile.Reparent(parent);
        tile.RegisterToCallback(n"OnRelease", this, n"OnApp");
        this.Hover(tile);

        let box = new inkCanvas();
        box.SetName(n"box");
        box.SetAnchor(inkEAnchor.TopCenter);
        box.SetAnchorPoint(Vector2(0.5, 0.0));
        box.SetSize(104.0, 104.0);
        box.Reparent(tile);
        RNImage(n"bg", RNShapes(), n"cell_bg", n"MainColors.Fullscreen_PrimaryBackgroundDarkest", 0.85).Reparent(box);
        RNImage(n"frame", RNShapes(), n"cell_fg", n"MainColors.Red", 0.6).Reparent(box);
        let icon = RNIcon(n"icon", RNAppIcon(name), 72.0, n"MainColors.Blue");
        icon.SetAnchor(inkEAnchor.Centered);
        icon.SetAnchorPoint(Vector2(0.5, 0.5));
        icon.Reparent(box);

        let labelText = RNText(n"label", 24, n"MainColors.Blue");
        labelText.SetAnchor(inkEAnchor.BottomCenter);
        labelText.SetAnchorPoint(Vector2(0.5, 1.0));
        labelText.SetHAlign(inkEHorizontalAlign.Center);
        labelText.SetText(label);
        labelText.Reparent(tile);
    }

    private func BuildTaskbar(desktop: ref<inkCompoundWidget>) {
        let taskbar = new inkCanvas();
        taskbar.SetName(n"taskbar");
        taskbar.SetAnchor(inkEAnchor.BottomFillHorizontaly);
        taskbar.SetAnchorPoint(Vector2(0.5, 1.0));
        taskbar.SetSize(100.0, 66.0);
        taskbar.Reparent(desktop);
        RNRect(n"bg", RNColor(0.05, 0.015, 0.025, 0.97)).Reparent(taskbar);
        let edge = RNRect(n"edge", RNColor(0.8, 0.15, 0.15, 0.9));
        edge.SetAnchor(inkEAnchor.TopFillHorizontaly);
        edge.SetSize(100.0, 2.0);
        edge.Reparent(taskbar);

        let left = new inkHorizontalPanel();
        left.SetName(n"left");
        left.SetMargin(inkMargin(14.0, 9.0, 0.0, 0.0));
        left.Reparent(taskbar);

        let start = new inkCanvas();
        start.SetName(n"start");
        start.SetSize(190.0, 48.0);
        start.SetMargin(inkMargin(0.0, 0.0, 16.0, 0.0));
        start.SetInteractive(true);
        start.Reparent(left);
        start.RegisterToCallback(n"OnRelease", this, n"OnStart");
        this.Hover(start);
        RNImage(n"bg", RNShapes(), n"button_big2_bg", n"MainColors.PanelDarkRed", 0.95).Reparent(start);
        RNImage(n"frame", RNShapes(), n"button_big2_fg", n"MainColors.Red", 1.0).Reparent(start);
        let startText = RNText(n"label", 28, n"MainColors.Red");
        startText.SetAnchor(inkEAnchor.Centered);
        startText.SetAnchorPoint(Vector2(0.5, 0.5));
        startText.SetHAlign(inkEHorizontalAlign.Center);
        startText.SetText("NC//OS");
        startText.Reparent(start);

        let tasks = new inkHorizontalPanel();
        tasks.SetName(n"tasks");
        tasks.Reparent(left);
        this.m_taskButtons = tasks;

        let tray = new inkHorizontalPanel();
        tray.SetName(n"tray");
        tray.SetAnchor(inkEAnchor.TopRight);
        tray.SetAnchorPoint(Vector2(1.0, 0.0));
        tray.SetMargin(inkMargin(0.0, 18.0, 28.0, 0.0));
        tray.Reparent(taskbar);
        let heat = RNText(n"heat", 26, n"MainColors.Yellow");
        heat.Reparent(tray);
        this.m_heat = heat;
        let clock = RNText(n"clock", 26, n"MainColors.Blue");
        clock.Reparent(tray);
        this.m_clock = clock;
    }

    private func BuildStartMenu(desktop: ref<inkCompoundWidget>) {
        let menu = new inkCanvas();
        menu.SetName(n"startMenu");
        menu.SetAnchor(inkEAnchor.BottomLeft);
        menu.SetAnchorPoint(Vector2(0.0, 1.0));
        menu.SetMargin(inkMargin(14.0, 0.0, 0.0, 72.0));
        menu.SetSize(420.0, 640.0);
        menu.SetVisible(false);
        menu.SetInteractive(true);
        menu.Reparent(desktop);
        this.m_startMenu = menu;
        RNImage(n"bg", RNShapes(), n"cell_bg", n"MainColors.Fullscreen_PrimaryBackgroundDarkest", 0.98).Reparent(menu);
        RNImage(n"frame", RNShapes(), n"cell_fg", n"MainColors.Red", 1.0).Reparent(menu);

        let list = new inkVerticalPanel();
        list.SetName(n"list");
        list.SetMargin(inkMargin(28.0, 24.0, 0.0, 0.0));
        list.Reparent(menu);
        let title = RNText(n"menuTitle", 30, n"MainColors.Red");
        title.SetMargin(inkMargin(0.0, 0.0, 0.0, 6.0));
        title.SetText("NC//OS");
        title.Reparent(list);
        let machine = RNText(n"machine", 22, n"MainColors.Yellow");
        machine.SetMargin(inkMargin(0.0, 0.0, 0.0, 18.0));
        machine.SetText(StrUpper(this.m_name));
        machine.Reparent(list);
        this.AddMenuItem(list, n"app_files", "Files");
        this.AddMenuItem(list, n"app_mail", "Mail");
        this.AddMenuItem(list, n"app_documents", "Documents");
        this.AddMenuItem(list, n"app_system", "System");
        this.AddMenuItem(list, n"app_browser", "Browser");
        this.AddMenuItem(list, n"app_market", "Stock exchange");
        this.AddMenuItem(list, n"app_terminal", "Terminal");
        this.AddMenuItem(list, n"app_deck", "Cyberdeck");
        this.AddMenuItem(list, n"app_exit", "Exit desktop");
    }

    private func AddMenuItem(parent: ref<inkCompoundWidget>, name: CName, label: String) {
        let item = new inkHorizontalPanel();
        item.SetName(name);
        item.SetMargin(inkMargin(0.0, 0.0, 0.0, 10.0));
        item.SetInteractive(true);
        item.Reparent(parent);
        item.RegisterToCallback(n"OnRelease", this, n"OnApp");
        this.Hover(item);
        let icon = RNIcon(n"icon", RNAppIcon(name), 44.0, n"MainColors.Blue");
        icon.Reparent(item);
        let text = RNText(n"label", 30, n"MainColors.Blue");
        text.SetMargin(inkMargin(16.0, 4.0, 0.0, 0.0));
        text.SetText(label);
        text.Reparent(item);
    }

    // --- window management -------------------------------------------------------

    private func FindWindow(kind: Int32) -> ref<RNWindow> {
        for window in this.m_windows {
            if window.m_kind == kind {
                return window;
            }
        }
        return null;
    }

    private func OpenWindow(kind: Int32, title: String) -> ref<RNWindow> {
        let layer = this.m_windowsLayer;
        let controller = this.m_controller;
        if !IsDefined(layer) || !IsDefined(controller) {
            return null;
        }
        // cascade new windows so they don't stack exactly
        let step = Cast<Float>(ArraySize(this.m_windows) % 6) * 40.0;
        this.m_nextId += 1;
        let window = RNWindow.Create(this, this.m_nextId, kind, title, layer, controller, 260.0 + step, 40.0 + step);
        ArrayPush(this.m_windows, window);
        this.Focus(window);
        return window;
    }

    private func OpenFiles(folder: String) {
        let window = this.FindWindow(1);
        if !IsDefined(window) {
            window = this.OpenWindow(1, "FILES");
        }
        if IsDefined(window) {
            window.OpenFolder(folder);
            window.SetMinimized(false);
            this.Focus(window);
            window.Draw();
        }
    }

    public func OpenDocument(index: Int32) {
        // one window per document; reuse it if it's already open
        for window in this.m_windows {
            if window.m_kind == 2 && window.m_docIndex == index {
                window.SetMinimized(false);
                this.Focus(window);
                return;
            }
        }
        let window = this.OpenWindow(2, StrUpper(StrAfterLast(this.m_paths[index], "/")));
        if IsDefined(window) {
            window.m_docIndex = index;
            window.Draw();
        }
    }

    private func OpenBrowser(url: String) {
        let window = this.FindWindow(4);
        if !IsDefined(window) {
            window = this.OpenWindow(4, "BROWSER");
        }
        if IsDefined(window) {
            window.SetMinimized(false);
            this.Focus(window);
            window.Navigate(url, true);
        }
    }

    public func OnPageReady(url: String) {
        for window in this.m_windows {
            if window.m_kind == 4 {
                window.OnPageReady(url);
            }
        }
    }

    public func RefreshTaskbarTitles() {
        this.RefreshTaskbar();
    }

    // --- other mods' sites -------------------------------------------------------

    public func GetDevice() -> ref<GameObject> {
        let controller = this.m_controller;
        if !IsDefined(controller) {
            return null;
        }
        return controller.GetOwnerEntity() as GameObject;
    }

    // Tells Lua which sites this computer has, for the portal.
    public func PushModSites() {
        let service = DeckService.Get();
        if !IsDefined(service) {
            return;
        }
        let sites = RNReadExtensionSites(this.GetDevice());
        for site in RNReadJournalSites(GetGameInstance()) {
            let duplicate = false;
            for existing in sites {
                if Equals(StrLower(existing.address), StrLower(site.address)) {
                    duplicate = true;
                }
            }
            if !duplicate {
                ArrayPush(sites, site);
            }
        }
        service.SetModSites(sites);
    }

    // A link clicked inside an embedded site page on this computer.
    public func RouteLink(device: ref<GameObject>, address: String) -> Bool {
        let mine = this.GetDevice();
        let desktop = this.m_desktop;
        if !IsDefined(mine) || !IsDefined(device) || !IsDefined(desktop) || !desktop.IsVisible() {
            return false;
        }
        if !Equals(mine.GetEntityID(), device.GetEntityID()) {
            return false;
        }
        for window in this.m_windows {
            if window.m_kind == 4 {
                let browser = window.GetBrowser();
                if IsDefined(browser) && browser.IsShowingExternal() {
                    browser.Navigate(address, true);
                    return true;
                }
            }
        }
        return false;
    }

    // Vanilla sites live in the computer's own browser: close the desktop and open it there.
    public func OpenInComputerBrowser(address: String) {
        let controller = this.m_controller;
        let desktop = this.m_desktop;
        if !IsDefined(controller) {
            return;
        }
        if IsDefined(desktop) {
            desktop.SetVisible(false);
        }
        controller.ShowInternet();
        let service = DeckService.Get();
        if IsDefined(service) {
            let browser = service.ComputerBrowserFor(this.GetDevice());
            if IsDefined(browser) {
                browser.RNLoad(address);
            }
        }
    }

    private func OpenTerminal() {
        let service = DeckService.Get();
        if IsDefined(service) {
            this.ConnectDeck(service);
        }
        let window = this.FindWindow(3);
        if !IsDefined(window) {
            window = this.OpenWindow(3, "TERMINAL");
        }
        if IsDefined(window) {
            window.SetMinimized(false);
            this.Focus(window);
            window.Draw();
            let input = window.GetInputWidget();
            if IsDefined(input) && IsDefined(this.m_controller) {
                this.m_controller.RequestSetFocus(input);
            }
        }
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

    public func Focus(window: ref<RNWindow>) {
        let layer = this.m_windowsLayer;
        if IsDefined(layer) && IsDefined(window.m_root) {
            layer.ReorderChild(window.m_root, layer.GetNumChildren() - 1);
        }
        this.m_focusedId = window.m_id;
        this.RefreshTaskbar();
    }

    public func Minimize(window: ref<RNWindow>) {
        window.SetMinimized(true);
        this.RefreshTaskbar();
    }

    public func CloseWindow(window: ref<RNWindow>) {
        let layer = this.m_windowsLayer;
        if IsDefined(layer) {
            window.Destroy(layer);
        }
        let kept: array<ref<RNWindow>>;
        for other in this.m_windows {
            if other.m_id != window.m_id {
                ArrayPush(kept, other);
            }
        }
        this.m_windows = kept;
        this.RefreshTaskbar();
    }

    private func RefreshTaskbar() {
        let tasks = this.m_taskButtons;
        if !IsDefined(tasks) {
            return;
        }
        tasks.RemoveAllChildren();
        for window in this.m_windows {
            let focused = !window.m_minimized && this.m_focusedId == window.m_id;
            window.SetFocused(focused);
            let button = new inkCanvas();
            button.SetName(StringToName("task" + IntToString(window.m_id)));
            button.SetSize(250.0, 48.0);
            button.SetMargin(inkMargin(0.0, 0.0, 10.0, 0.0));
            button.SetInteractive(true);
            button.Reparent(tasks);
            button.RegisterToCallback(n"OnRelease", this, n"OnTask");
            this.Hover(button);
            RNImage(n"bg", RNShapes(), n"cell_bg", focused ? n"MainColors.PanelDarkRed" : n"MainColors.Fullscreen_PrimaryBackgroundDarkest", 0.9).Reparent(button);
            RNImage(n"frame", RNShapes(), n"cell_fg", n"MainColors.Red", focused ? 1.0 : 0.4).Reparent(button);
            let label = RNText(n"label", 22, focused ? n"MainColors.Red" : n"MainColors.Blue");
            label.SetAnchor(inkEAnchor.CenterLeft);
            label.SetAnchorPoint(Vector2(0.0, 0.5));
            label.SetMargin(inkMargin(16.0, 0.0, 0.0, 0.0));
            label.SetText(window.m_minimized ? "(" + RNShorten(window.m_title, 16) + ")" : RNShorten(window.m_title, 18));
            label.Reparent(button);
        }
        this.UpdateTray();
    }

    private func UpdateTray() {
        if IsDefined(this.m_heat) {
            let service = DeckService.Get();
            let heat = IsDefined(service) ? service.GetHeat() : 0;
            this.m_heat.SetText("HEAT " + IntToString(heat) + "      ");
            this.m_heat.BindProperty(n"tintColor", heat >= 50 ? n"MainColors.Red" : n"MainColors.Yellow");
        }
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

    // --- dragging ---------------------------------------------------------------

    public func BeginDrag(window: ref<RNWindow>, screenPosition: Vector2) {
        let layer = this.m_windowsLayer;
        if !IsDefined(layer) || !IsDefined(window.m_root) {
            return;
        }
        this.Focus(window);
        let local = WidgetUtils.GlobalToLocal(layer, screenPosition);
        let at = window.m_root.GetTranslation();
        this.m_grab = Vector2(local.X - at.X, local.Y - at.Y);
        this.m_dragging = window;
    }

    protected cb func OnMouseMove(e: ref<inkPointerEvent>) -> Bool {
        // mouse wheel scrolls a browser page under the cursor
        if e.IsAction(n"mouse_wheel") {
            for candidate in this.m_windows {
                let browser = candidate.GetBrowser();
                if candidate.m_kind == 4 && !candidate.m_minimized && IsDefined(browser) && browser.Contains(e.GetScreenSpacePosition()) {
                    browser.Scroll(e.GetAxisData() > 0.0 ? -2 : 2);
                    return false;
                }
            }
            return false;
        }
        let window = this.m_dragging;
        let layer = this.m_windowsLayer;
        if !IsDefined(window) || !IsDefined(layer) || !IsDefined(window.m_root) {
            return false;
        }
        if e.IsAction(n"mouse_x") || e.IsAction(n"mouse_y") {
            let local = WidgetUtils.GlobalToLocal(layer, e.GetScreenSpacePosition());
            // keep the title bar reachable
            let x = MaxF(-900.0, local.X - this.m_grab.X);
            let y = MaxF(0.0, local.Y - this.m_grab.Y);
            window.m_root.SetTranslation(x, y);
        }
        return false;
    }

    protected cb func OnMouseUp(e: ref<inkPointerEvent>) -> Bool {
        if IsDefined(this.m_dragging) && (e.IsAction(n"click") || e.IsAction(n"mouse_left")) {
            this.m_dragging = null;
        }
        return false;
    }

    // --- called by DeckService ---------------------------------------------------

    public func OnDeckChanged() {
        for window in this.m_windows {
            if window.m_kind == 3 {
                window.Draw();
            }
        }
    }

    public func OnFilesChanged(key: String) {
        if Equals(key, this.m_key) {
            this.ReloadFiles();
            this.RedrawFileWindows();
        }
    }

    public func OnHomeChanged() {
        if this.m_isHome {
            this.ReloadFiles();
            this.RedrawFileWindows();
        }
    }

    public func OnTrayChanged() {
        this.UpdateTray();
    }

    private func RedrawFileWindows() {
        for window in this.m_windows {
            if window.m_kind == 1 || window.m_kind == 2 {
                window.Draw();
            }
        }
    }

    // --- clicks -----------------------------------------------------------------

    protected cb func OnLaunch(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") {
            this.ReloadFiles();
            this.m_desktop.SetVisible(true);
            this.RefreshTaskbar();
        }
        return false;
    }

    protected cb func OnStart(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") && IsDefined(this.m_startMenu) {
            this.m_startMenu.SetVisible(!this.m_startMenu.IsVisible());
            this.UpdateTray();
        }
        return false;
    }

    // icons and start menu items share this: the widget name says which app
    protected cb func OnApp(e: ref<inkPointerEvent>) -> Bool {
        if !e.IsAction(n"click") {
            return false;
        }
        this.m_startMenu.SetVisible(false);
        let app = e.GetCurrentTarget().GetName();
        if Equals(app, n"app_files") {
            this.OpenFiles("");
        } else if Equals(app, n"app_mail") {
            this.OpenFiles("Mail");
        } else if Equals(app, n"app_documents") {
            this.OpenFiles("Documents");
        } else if Equals(app, n"app_system") {
            this.OpenFiles("System");
        } else if Equals(app, n"app_browser") {
            this.OpenBrowser("nc://home");
        } else if Equals(app, n"app_market") {
            this.OpenBrowser("market://");
        } else if Equals(app, n"app_terminal") {
            this.OpenTerminal();
        } else if Equals(app, n"app_deck") {
            this.OpenDeck();
        } else if Equals(app, n"app_exit") {
            this.m_desktop.SetVisible(false);
        }
        return false;
    }

    private func OpenDeck() {
        let service = DeckService.Get();
        if IsDefined(service) {
            this.ConnectDeck(service);
            service.Open();
        }
    }

    protected cb func OnTask(e: ref<inkPointerEvent>) -> Bool {
        if !e.IsAction(n"click") {
            return false;
        }
        let id = RNNameNumber(e.GetCurrentTarget().GetName(), "task");
        for window in this.m_windows {
            if window.m_id == id {
                if window.m_minimized {
                    window.SetMinimized(false);
                    this.Focus(window);
                } else {
                    if this.m_focusedId == window.m_id {
                        this.Minimize(window);
                    } else {
                        this.Focus(window);
                    }
                }
                return false;
            }
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
