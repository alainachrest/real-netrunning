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

public class DeckService extends ScriptableService {
    private let m_lines: array<String>;
    private let m_kinds: array<Int32>;
    private let m_pending: array<String>;
    private let m_history: array<String>;
    private let m_prompt: String;
    private let m_status: String;
    private let m_trace: Float;
    private let m_popup: ref<DeckPopup>;

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

        this.m_status.SetText(this.m_service.GetStatus());

        let trace = this.m_service.GetTrace();
        if trace < 0.0 {
            this.m_trace.SetText("");
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
                row.SetText("");
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
        let self = new DeckPopup();
        self.m_service = service;
        self.CreateInstance();
        return self;
    }
}
