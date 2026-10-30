// -----------------------------------------------------------------------------
// Real Netrunning - native cyberdeck popup
// -----------------------------------------------------------------------------
//
// The deck's logic (commands, networks, trace) lives in the CET Lua mod.
// This file only draws it in the game's own UI, using Codeware's InGamePopup
// (pauses V's controls and slows time like the game's own popups) and
// TextInput (native typing).
//
// Lua talks to DeckService through the ScriptableServiceContainer:
//   AddLine / ClearLines / SetPrompt / SetStatus / SetTrace  (Lua -> screen)
//   HasCommand / TakeCommand                                  (screen -> Lua)
//   Open / Close / IsOpen
//
// Requires Codeware 1.21 or newer.

module RealNetrunning
import Codeware.UI.*

// One file Lua generated for a computer's simulated filesystem.
public class RNFileEntry {
    public let key: String;
    public let path: String;
    public let text: String;
    public let locked: Bool;
}

// One line of a Browser page. kind: 0 text, 1 title, 2 link, 3 good, 4 bad, 5 note.
public class RNPageLine {
    public let url: String;
    public let text: String;
    public let link: String;
    public let kind: Int32;
}

public class DeckService extends ScriptableService {
    private let m_lines: array<String>;
    private let m_kinds: array<Int32>;
    private let m_pending: array<String>;
    private let m_history: array<String>;
    private let m_prompt: String;
    private let m_status: String;
    private let m_trace: Float;
    private let m_popup: ref<DeckPopup>;

    // computer desktops (see Desktop.reds)
    private let m_machineRequests: array<String>;
    private let m_files: array<ref<RNFileEntry>>;
    private let m_filesVersion: Int32;
    private let m_terminals: array<wref<RNDesktop>>;
    private let m_machineKeys: array<String>;
    private let m_machineAddrs: array<String>;

    // V's home computers: saved documents, kept per save by Lua
    private let m_saveNames: array<String>;
    private let m_saveTexts: array<String>;
    private let m_homeNames: array<String>;
    private let m_homeTexts: array<String>;
    private let m_heat: Int32;

    // Browser pages, rendered by Lua on request
    private let m_pageRequests: array<String>;
    private let m_pageUrls: array<String>;
    private let m_pageTitles: array<String>;
    private let m_pageCanonical: array<String>;
    private let m_pageLines: array<ref<RNPageLine>>;

    // Fixed limits, and defaults that don't rely on a start-up callback.
    private let m_traceSet: Bool;

    private func MaxLines() -> Int32 { return 400; }
    private func MaxHistory() -> Int32 { return 50; }

    // --- Lua -> screen ------------------------------------------------------

    public func AddLine(text: String, kind: Int32) {
        ArrayPush(this.m_lines, text);
        ArrayPush(this.m_kinds, kind);

        while ArraySize(this.m_lines) > this.MaxLines() {
            ArrayErase(this.m_lines, 0);
            ArrayErase(this.m_kinds, 0);
        }

        this.Refresh();
    }

    public func ClearLines() {
        ArrayClear(this.m_lines);
        ArrayClear(this.m_kinds);
        this.Refresh();
    }

    public func SetPrompt(prompt: String) {
        this.m_prompt = prompt;
        this.Refresh();
    }

    public func SetStatus(status: String) {
        this.m_status = status;
        this.Refresh();
    }

    // trace 0-100 while connected, below 0 to hide
    public func SetTrace(trace: Float) {
        this.m_trace = trace;
        this.m_traceSet = true;
        this.Refresh();
    }

    // --- screen -> Lua ------------------------------------------------------

    public func HasCommand() -> Bool {
        return ArraySize(this.m_pending) > 0;
    }

    public func TakeCommand() -> String {
        if ArraySize(this.m_pending) == 0 {
            return "";
        }
        let command = this.m_pending[0];
        ArrayErase(this.m_pending, 0);
        return command;
    }

    public func Submit(text: String) {
        if StrLen(text) == 0 {
            return;
        }
        ArrayPush(this.m_pending, text);
        ArrayPush(this.m_history, text);
        while ArraySize(this.m_history) > this.MaxHistory() {
            ArrayErase(this.m_history, 0);
        }
    }

    // --- popup --------------------------------------------------------------

    public func IsOpen() -> Bool {
        return IsDefined(this.m_popup);
    }

    public func Open() -> Bool {
        if IsDefined(this.m_popup) {
            return true;
        }

        let layer = GameInstance.GetInkSystem().GetLayer(n"inkHUDLayer");
        if !IsDefined(layer) {
            return false;
        }

        // the layer returns the base controller type; Open needs an inkGameController
        let controller = layer.GetGameController() as inkGameController;
        if !IsDefined(controller) {
            return false;
        }

        let popup = DeckPopup.Create(this);
        this.m_popup = popup;
        popup.Open(controller);
        return true;
    }

    public func Close() {
        if IsDefined(this.m_popup) {
            this.m_popup.Close();
        }
    }

    public func OnPopupClosed() {
        this.m_popup = null;
    }

    public func Refresh() {
        if IsDefined(this.m_popup) {
            this.m_popup.Refresh();
        }
        for terminal in this.m_terminals {
            if IsDefined(terminal) {
                terminal.OnDeckChanged();
            }
        }
    }

    // --- computer desktops ----------------------------------------------------

    public static func Get() -> ref<DeckService> {
        return GameInstance.GetScriptableServiceContainer()
            .GetService(n"RealNetrunning.DeckService") as DeckService;
    }

    // Each desktop registers once when it is built; entries for computers that
    // have since unloaded simply become undefined and are skipped.
    public func RegisterTerminal(desktop: ref<RNDesktop>) {
        let live: array<wref<RNDesktop>>;
        for terminal in this.m_terminals {
            if IsDefined(terminal) {
                ArrayPush(live, terminal);
            }
        }
        ArrayPush(live, desktop);
        this.m_terminals = live;
    }

    // A desktop asks Lua for a computer's generated files. Lua takes "key|name".
    public func RequestMachine(key: String, name: String) {
        ArrayPush(this.m_machineRequests, key + "|" + name);
    }

    public func HasMachineRequest() -> Bool {
        return ArraySize(this.m_machineRequests) > 0;
    }

    public func TakeMachineRequest() -> String {
        if ArraySize(this.m_machineRequests) == 0 {
            return "";
        }
        let request = this.m_machineRequests[0];
        ArrayErase(this.m_machineRequests, 0);
        return request;
    }

    public func ClearMachineFiles(key: String) {
        let kept: array<ref<RNFileEntry>>;
        for entry in this.m_files {
            if NotEquals(entry.key, key) {
                ArrayPush(kept, entry);
            }
        }
        this.m_files = kept;
    }

    public func AddMachineFile(key: String, path: String, text: String, locked: Bool) {
        let entry = new RNFileEntry();
        entry.key = key;
        entry.path = path;
        entry.text = text;
        entry.locked = locked;
        ArrayPush(this.m_files, entry);
    }

    // Lua calls this after adding a machine's files, so open desktops redraw.
    public func MachineFilesReady(key: String) {
        this.m_filesVersion += 1;
        for terminal in this.m_terminals {
            if IsDefined(terminal) {
                terminal.OnFilesChanged(key);
            }
        }
    }

    // Lua tells us which network address a computer was registered under.
    public func SetMachineAddr(key: String, addr: String) {
        let i = 0;
        while i < ArraySize(this.m_machineKeys) {
            if Equals(this.m_machineKeys[i], key) {
                this.m_machineAddrs[i] = addr;
                return;
            }
            i += 1;
        }
        ArrayPush(this.m_machineKeys, key);
        ArrayPush(this.m_machineAddrs, addr);
    }

    public func GetMachineAddr(key: String) -> String {
        let i = 0;
        while i < ArraySize(this.m_machineKeys) {
            if Equals(this.m_machineKeys[i], key) {
                return this.m_machineAddrs[i];
            }
            i += 1;
        }
        return "";
    }

    // --- browser pages ---------------------------------------------------------------

    public func RequestPage(url: String) {
        ArrayPush(this.m_pageRequests, url);
    }

    public func HasPageRequest() -> Bool {
        return ArraySize(this.m_pageRequests) > 0;
    }

    public func TakePageRequest() -> String {
        if ArraySize(this.m_pageRequests) == 0 {
            return "";
        }
        let url = this.m_pageRequests[0];
        ArrayErase(this.m_pageRequests, 0);
        return url;
    }

    private func PageIndex(url: String) -> Int32 {
        let i = 0;
        while i < ArraySize(this.m_pageUrls) {
            if Equals(this.m_pageUrls[i], url) {
                return i;
            }
            i += 1;
        }
        return -1;
    }

    // Lua: BeginPage, then AddPageLine for each line, then PageReady.
    public func BeginPage(url: String, title: String, canonical: String) {
        let index = this.PageIndex(url);
        if index < 0 {
            ArrayPush(this.m_pageUrls, url);
            ArrayPush(this.m_pageTitles, title);
            ArrayPush(this.m_pageCanonical, canonical);
        } else {
            this.m_pageTitles[index] = title;
            this.m_pageCanonical[index] = canonical;
        }
        let kept: array<ref<RNPageLine>>;
        for line in this.m_pageLines {
            if NotEquals(line.url, url) {
                ArrayPush(kept, line);
            }
        }
        this.m_pageLines = kept;
    }

    public func AddPageLine(url: String, text: String, link: String, kind: Int32) {
        let line = new RNPageLine();
        line.url = url;
        line.text = text;
        line.link = link;
        line.kind = kind;
        ArrayPush(this.m_pageLines, line);
    }

    public func PageReady(url: String) {
        for terminal in this.m_terminals {
            if IsDefined(terminal) {
                terminal.OnPageReady(url);
            }
        }
    }

    public func GetPageTitle(url: String) -> String {
        let index = this.PageIndex(url);
        return index >= 0 ? this.m_pageTitles[index] : "";
    }

    public func GetPageCanonical(url: String) -> String {
        let index = this.PageIndex(url);
        return index >= 0 ? this.m_pageCanonical[index] : url;
    }

    public func GetPageLines(url: String) -> array<ref<RNPageLine>> {
        let result: array<ref<RNPageLine>>;
        for line in this.m_pageLines {
            if Equals(line.url, url) {
                ArrayPush(result, line);
            }
        }
        return result;
    }

    // --- tray --------------------------------------------------------------------

    public func SetHeat(heat: Int32) {
        this.m_heat = heat;
        for terminal in this.m_terminals {
            if IsDefined(terminal) {
                terminal.OnTrayChanged();
            }
        }
    }

    public func GetHeat() -> Int32 { return this.m_heat; }

    // --- saving documents to V's home computers -------------------------------------

    public func RequestSaveToHome(name: String, text: String) {
        ArrayPush(this.m_saveNames, name);
        ArrayPush(this.m_saveTexts, text);
    }

    public func HasSaveRequest() -> Bool {
        return ArraySize(this.m_saveNames) > 0;
    }

    // Lua calls TakeSaveName then TakeSaveText for each request.
    public func TakeSaveName() -> String {
        if ArraySize(this.m_saveNames) == 0 {
            return "";
        }
        let name = this.m_saveNames[0];
        ArrayErase(this.m_saveNames, 0);
        return name;
    }

    public func TakeSaveText() -> String {
        if ArraySize(this.m_saveTexts) == 0 {
            return "";
        }
        let text = this.m_saveTexts[0];
        ArrayErase(this.m_saveTexts, 0);
        return text;
    }

    public func ClearHomeFiles() {
        ArrayClear(this.m_homeNames);
        ArrayClear(this.m_homeTexts);
    }

    public func AddHomeFile(name: String, text: String) {
        ArrayPush(this.m_homeNames, name);
        ArrayPush(this.m_homeTexts, text);
    }

    public func HomeFilesReady() {
        for terminal in this.m_terminals {
            if IsDefined(terminal) {
                terminal.OnHomeChanged();
            }
        }
    }

    public func GetHomeFileCount() -> Int32 { return ArraySize(this.m_homeNames); }
    public func GetHomeFileName(index: Int32) -> String { return this.m_homeNames[index]; }
    public func GetHomeFileText(index: Int32) -> String { return this.m_homeTexts[index]; }

    public func GetMachineFiles(key: String) -> array<ref<RNFileEntry>> {
        let result: array<ref<RNFileEntry>>;
        for entry in this.m_files {
            if Equals(entry.key, key) {
                ArrayPush(result, entry);
            }
        }
        return result;
    }

    // --- read by the popup --------------------------------------------------

    public func GetLineCount() -> Int32 { return ArraySize(this.m_lines); }
    public func GetLine(index: Int32) -> String { return this.m_lines[index]; }
    public func GetKind(index: Int32) -> Int32 { return this.m_kinds[index]; }
    public func GetPrompt() -> String { return StrLen(this.m_prompt) > 0 ? this.m_prompt : "deck>"; }
    public func GetStatus() -> String { return this.m_status; }
    public func GetTrace() -> Float { return this.m_traceSet ? this.m_trace : -1.0; }
    public func GetHistoryCount() -> Int32 { return ArraySize(this.m_history); }
    public func GetHistory(index: Int32) -> String { return this.m_history[index]; }
}

public class DeckPopup extends InGamePopup {
    protected let m_service: wref<DeckService>;
    protected let m_header: ref<InGamePopupHeader>;
    protected let m_footer: ref<InGamePopupFooter>;
    protected let m_content: ref<InGamePopupContent>;
    protected let m_input: ref<TextInput>;

    protected let m_status: wref<inkText>;
    protected let m_trace: wref<inkText>;
    protected let m_prompt: wref<inkText>;
    protected let m_rows: array<wref<inkText>>;

    protected let m_visibleRows: Int32;
    protected let m_scroll: Int32;
    protected let m_historyIndex: Int32;

    protected cb func OnCreate() {
        super.OnCreate();

        this.m_visibleRows = 14;
        ArrayClear(this.m_rows); // in case widgets are ever rebuilt

        this.m_header = InGamePopupHeader.Create();
        this.m_header.SetTitle("REAL NETRUNNING");
        this.m_header.SetFluffLeft("CYBERDECK");
        this.m_header.Reparent(this);

        this.m_footer = InGamePopupFooter.Create();
        this.m_footer.SetFluffText("NETWATCH COMPLIANT // NOT");
        this.m_footer.GetHints().AddButtonHint(n"cancel", "Close deck");
        this.m_footer.Reparent(this);

        this.m_content = InGamePopupContent.Create();
        this.m_content.Reparent(this);

        let panel = new inkVerticalPanel();
        panel.SetName(n"deck");
        panel.SetAnchor(inkEAnchor.Fill);
        panel.Reparent(this.m_content.GetRootCompoundWidget());

        // attach each widget while a local strong ref holds it, then keep a weak ref
        let status = this.CreateText(n"status", 24, n"MainColors.Yellow");
        status.Reparent(panel);
        this.m_status = status;

        let trace = this.CreateText(n"trace", 24, n"MainColors.Red");
        trace.Reparent(panel);
        this.m_trace = trace;

        let i = 0;
        while i < this.m_visibleRows {
            let row = this.CreateText(StringToName("row" + IntToString(i)), 26, n"MainColors.Blue");
            row.Reparent(panel);
            ArrayPush(this.m_rows, row);
            i += 1;
        }

        let inputRow = new inkHorizontalPanel();
        inputRow.SetName(n"inputRow");
        inputRow.SetMargin(inkMargin(0.0, 16.0, 0.0, 0.0));
        inputRow.Reparent(panel);

        let prompt = this.CreateText(n"prompt", 26, n"MainColors.Blue");
        prompt.SetMargin(inkMargin(0.0, 14.0, 16.0, 0.0));
        prompt.Reparent(inputRow);
        this.m_prompt = prompt;

        this.m_input = TextInput.Create();
        this.m_input.SetName(n"command");
        this.m_input.SetMaxLength(200);
        this.m_input.SetWidth(1000.0);
        this.m_input.Reparent(inputRow);
        this.m_input.RegisterToCallback(n"OnInputKey", this, n"OnDeckKey");
    }

    protected func CreateText(name: CName, size: Int32, color: CName) -> ref<inkText> {
        let text = new inkText();
        text.SetName(name);
        text.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        text.SetFontStyle(n"Medium");
        text.SetFontSize(size);
        // without fit-to-content a text widget has zero size and draws nothing
        text.SetFitToContent(true);
        text.SetHAlign(inkEHorizontalAlign.Left);
        text.SetVAlign(inkEVerticalAlign.Top);
        text.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
        text.BindProperty(n"tintColor", color);
        text.SetText("");
        return text;
    }

    protected cb func OnShown() {
        super.OnShown();
        this.m_historyIndex = -1;
        this.Refresh();
        this.GetGameController().RequestSetFocus(this.m_input.GetRootWidget());
    }

    protected cb func OnHide() {
        super.OnHide();
        if IsDefined(this.m_service) {
            this.m_service.OnPopupClosed();
        }
    }

    protected cb func OnDeckKey(event: ref<inkKeyInputEvent>) -> Bool {
        if NotEquals(event.GetAction(), EInputAction.IACT_Press) {
            return false;
        }

        switch event.GetKey() {
            case EInputKey.IK_Enter:
                this.m_service.Submit(this.m_input.GetText());
                this.m_input.SetText("");
                this.m_scroll = 0;
                this.m_historyIndex = -1;
                break;
            case EInputKey.IK_Up:
                this.StepHistory(-1);
                break;
            case EInputKey.IK_Down:
                this.StepHistory(1);
                break;
            case EInputKey.IK_PageUp:
                this.m_scroll += this.m_visibleRows - 2;
                this.Refresh();
                break;
            case EInputKey.IK_PageDown:
                this.m_scroll = Max(0, this.m_scroll - (this.m_visibleRows - 2));
                this.Refresh();
                break;
        }
        return false;
    }

    protected func StepHistory(step: Int32) {
        let count = this.m_service.GetHistoryCount();
        if count == 0 {
            return;
        }
        if this.m_historyIndex < 0 {
            this.m_historyIndex = count;
        }
        this.m_historyIndex = Clamp(this.m_historyIndex + step, 0, count);
        if this.m_historyIndex >= count {
            this.m_input.SetText("");
        } else {
            this.m_input.SetText(this.m_service.GetHistory(this.m_historyIndex));
        }
    }

    public func Refresh() {
        if !IsDefined(this.m_service) || !IsDefined(this.m_status) {
            return;
        }

        let status = this.m_service.GetStatus();
        this.m_status.SetText(StrLen(status) > 0 ? status : " ");

        let trace = this.m_service.GetTrace();
        if trace < 0.0 {
            this.m_trace.SetText(" ");
        } else {
            this.m_trace.SetText("TRACE " + IntToString(Cast<Int32>(trace)) + "%");
        }

        this.m_prompt.SetText(this.m_service.GetPrompt());

        let total = this.m_service.GetLineCount();
        let maxScroll = Max(0, total - this.m_visibleRows);
        this.m_scroll = Clamp(this.m_scroll, 0, maxScroll);
        let last = total - this.m_scroll;
        let first = Max(0, last - this.m_visibleRows);

        let i = 0;
        while i < this.m_visibleRows {
            let row = this.m_rows[i];
            let index = first + i;
            if index < last {
                row.SetText(this.m_service.GetLine(index));
                row.BindProperty(n"tintColor", this.ColorFor(this.m_service.GetKind(index)));
            } else {
                row.SetText(" ");
            }
            i += 1;
        }
    }

    // 0 out, 1 command, 2 ok, 3 warning, 4 error
    protected func ColorFor(kind: Int32) -> CName {
        switch kind {
            case 1: return n"MainColors.White";
            case 2: return n"MainColors.Green";
            case 3: return n"MainColors.Yellow";
            case 4: return n"MainColors.Red";
            default: return n"MainColors.Blue";
        }
    }

    public func UseCursor() -> Bool {
        return true;
    }

    public static func Create(service: ref<DeckService>) -> ref<DeckPopup> {
        // Don't call CreateInstance here: Codeware creates the popup's widgets when it
        // attaches it to the screen. Creating them early built a second, invisible set.
        let self = new DeckPopup();
        self.m_service = service;
        return self;
    }
}
