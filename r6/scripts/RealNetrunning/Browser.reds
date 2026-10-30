// -----------------------------------------------------------------------------
// Real Netrunning - desktop web browser
// -----------------------------------------------------------------------------
//
// Draws inside a desktop window: a tab, a toolbar (back, forward, reload, home),
// an address bar you can type a URL or search into, the page, a scrollbar and a
// status bar that shows where a link goes.
//
// Pages are built by the Lua mod (modules/web.lua) as blocks and handed over
// through DeckService. Block types:
//   1 banner   2 nav      3 heading  4 text     5 link     6 button   7 card
//   8 row      9 chart   10 divider 11 notice  12 icon    13 field
// Consecutive nav, button and icon blocks are drawn side by side.

module RealNetrunning
import Codeware.UI.*

public class RNBrowserView {
    private let m_desktop: wref<RNDesktop>;
    private let m_controller: wref<inkGameController>;
    private let m_root: wref<inkCanvas>;

    private let m_tabText: wref<inkText>;
    private let m_tabAccent: wref<inkImage>;
    private let m_lock: wref<inkText>;
    private let m_address: ref<TextInput>;
    private let m_viewport: wref<inkScrollArea>;
    private let m_content: wref<inkVerticalPanel>;
    private let m_status: wref<inkText>;
    private let m_thumb: wref<inkRectangle>;

    private let m_url: String;
    private let m_requested: String;
    private let m_back: array<String>;
    private let m_forward: array<String>;
    private let m_title: String;
    private let m_theme: CName;
    private let m_blocks: array<ref<RNPageBlock>>;
    private let m_unitStart: array<Int32>;
    private let m_unitEnd: array<Int32>;
    private let m_offset: Float;       // how far the page is scrolled, in pixels
    private let m_estimate: Float;     // estimated page height, used until layout is known

    // layout, in window coordinates (the window is 1320 x 780)
    private func ContentTop() -> Float { return 176.0; }
    private func ContentBottom() -> Float { return 742.0; }
    private func ContentWidth() -> Float { return 1220.0; }
    private func ViewportHeight() -> Float { return 520.0; }

    public static func Create(desktop: wref<RNDesktop>, root: ref<inkCanvas>, controller: ref<inkGameController>) -> ref<RNBrowserView> {
        let self = new RNBrowserView();
        self.m_desktop = desktop;
        self.m_controller = controller;
        self.m_root = root;
        self.m_theme = n"MainColors.Blue";
        self.Build(root, controller);
        return self;
    }

    public func GetTitle() -> String {
        return this.m_title;
    }

    private func Hover(widget: ref<inkWidget>) {
        if IsDefined(this.m_desktop) {
            this.m_desktop.Hover(widget);
        }
    }

    // --- chrome -----------------------------------------------------------------

    private func Build(root: ref<inkCanvas>, controller: ref<inkGameController>) {
        // tab strip
        let tab = new inkCanvas();
        tab.SetName(n"tab");
        tab.SetSize(420.0, 44.0);
        tab.SetTranslation(16.0, 60.0);
        tab.Reparent(root);
        RNImage(n"bg", RNShapes(), n"button_big2_bg", n"MainColors.PanelDarkRed", 0.9).Reparent(tab);
        let accent = RNImage(n"frame", RNShapes(), n"button_big2_fg", n"MainColors.Blue", 1.0);
        accent.Reparent(tab);
        this.m_tabAccent = accent;
        let tabText = RNText(n"title", 24, n"MainColors.Blue");
        tabText.SetAnchor(inkEAnchor.CenterLeft);
        tabText.SetAnchorPoint(Vector2(0.0, 0.5));
        tabText.SetMargin(inkMargin(18.0, 0.0, 0.0, 0.0));
        tabText.SetText("New tab");
        tabText.Reparent(tab);
        this.m_tabText = tabText;

        // toolbar
        let toolbar = new inkHorizontalPanel();
        toolbar.SetName(n"toolbar");
        toolbar.SetTranslation(16.0, 112.0);
        toolbar.Reparent(root);
        this.AddToolButton(toolbar, n"back", "<", n"OnBack");
        this.AddToolButton(toolbar, n"forward", ">", n"OnForward");
        this.AddToolButton(toolbar, n"reload", "R", n"OnReload");
        this.AddToolButton(toolbar, n"home", "H", n"OnHome");

        let bar = new inkCanvas();
        bar.SetName(n"addressBar");
        bar.SetSize(1020.0, 52.0);
        bar.SetMargin(inkMargin(12.0, 0.0, 0.0, 0.0));
        bar.Reparent(toolbar);
        RNImage(n"bg", RNShapes(), n"cell_bg", n"MainColors.Fullscreen_PrimaryBackgroundDarkest", 1.0).Reparent(bar);
        RNImage(n"frame", RNShapes(), n"cell_fg", n"MainColors.Blue", 0.6).Reparent(bar);
        let fields = new inkHorizontalPanel();
        fields.SetName(n"fields");
        fields.SetMargin(inkMargin(14.0, 6.0, 0.0, 0.0));
        fields.Reparent(bar);
        let lock = RNText(n"lock", 22, n"MainColors.Green");
        lock.SetMargin(inkMargin(0.0, 10.0, 12.0, 0.0));
        lock.SetText("NC//NET");
        lock.Reparent(fields);
        this.m_lock = lock;
        this.m_address = TextInput.Create();
        this.m_address.SetName(n"rn_address");
        this.m_address.SetMaxLength(200);
        this.m_address.SetWidth(880.0);
        this.m_address.Reparent(fields, controller);
        this.m_address.RegisterToCallback(n"OnInputKey", this, n"OnAddressKey");

        // page area
        let page = new inkCanvas();
        page.SetName(n"page");
        page.SetSize(1288.0, this.ContentBottom() - this.ContentTop());
        page.SetTranslation(16.0, this.ContentTop());
        page.Reparent(root);
        RNRect(n"bg", RNColor(0.02, 0.025, 0.04, 1.0)).Reparent(page);
        // The page is built once and slid up and down inside a clipped scroll area,
        // so scrolling never creates or destroys widgets.
        let viewport = new inkScrollArea();
        viewport.SetName(n"viewport");
        viewport.SetAnchor(inkEAnchor.Fill);
        viewport.SetMargin(inkMargin(24.0, 16.0, 40.0, 12.0));
        viewport.SetRenderTransformPivot(Vector2(0.0, 0.0));
        viewport.SetFitToContentDirection(inkFitToContentDirection.Horizontal);
        viewport.SetConstrainContentPosition(false);
        viewport.SetUseInternalMask(true);
        viewport.Reparent(page);
        this.m_viewport = viewport;
        let content = new inkVerticalPanel();
        content.SetName(n"content");
        content.SetFitToContent(true);
        content.SetRenderTransformPivot(Vector2(0.0, 0.0));
        content.Reparent(viewport);
        this.m_content = content;

        // scrollbar
        let track = RNRect(n"track", RNColor(0.2, 0.05, 0.06, 0.6));
        track.SetAnchor(inkEAnchor.TopRight);
        track.SetAnchorPoint(Vector2(1.0, 0.0));
        track.SetSize(8.0, this.ContentBottom() - this.ContentTop() - 16.0);
        track.SetMargin(inkMargin(0.0, 8.0, 10.0, 0.0));
        track.Reparent(page);
        let thumb = new inkRectangle();
        thumb.SetName(n"thumb");
        thumb.SetAnchor(inkEAnchor.TopRight);
        thumb.SetAnchorPoint(Vector2(1.0, 0.0));
        thumb.SetSize(8.0, 80.0);
        thumb.SetMargin(inkMargin(0.0, 8.0, 10.0, 0.0));
        thumb.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
        thumb.BindProperty(n"tintColor", n"MainColors.Red");
        thumb.Reparent(page);
        this.m_thumb = thumb;

        // status bar
        let status = RNText(n"status", 22, n"MainColors.Yellow");
        status.SetTranslation(22.0, this.ContentBottom() + 6.0);
        status.SetText("Ready");
        status.Reparent(root);
        this.m_status = status;
    }

    private func AddToolButton(parent: ref<inkCompoundWidget>, name: CName, label: String, callback: CName) {
        let button = new inkCanvas();
        button.SetName(name);
        button.SetSize(56.0, 52.0);
        button.SetMargin(inkMargin(0.0, 0.0, 8.0, 0.0));
        button.SetInteractive(true);
        button.Reparent(parent);
        button.RegisterToCallback(n"OnRelease", this, callback);
        this.Hover(button);
        RNImage(n"bg", RNShapes(), n"cell_bg", n"MainColors.Fullscreen_PrimaryBackgroundDarkest", 1.0).Reparent(button);
        RNImage(n"frame", RNShapes(), n"cell_fg", n"MainColors.Red", 0.7).Reparent(button);
        let text = RNText(n"label", 28, n"MainColors.Blue");
        text.SetAnchor(inkEAnchor.Centered);
        text.SetAnchorPoint(Vector2(0.5, 0.5));
        text.SetHAlign(inkEHorizontalAlign.Center);
        text.SetText(label);
        text.Reparent(button);
    }

    // --- navigation ---------------------------------------------------------------

    public func Navigate(url: String, remember: Bool) {
        if StrLen(url) == 0 {
            return;
        }
        if remember && StrLen(this.m_url) > 0 && NotEquals(this.m_url, url) && !StrBeginsWith(url, "do://") {
            ArrayPush(this.m_back, this.m_url);
            while ArraySize(this.m_back) > 30 {
                ArrayErase(this.m_back, 0);
            }
            ArrayClear(this.m_forward);
        }
        this.m_requested = url;
        if !StrBeginsWith(url, "do://") {
            this.m_url = url;
            this.m_address.SetText(url);
        }
        this.SetStatus("Connecting to " + url + " ...");
        let service = DeckService.Get();
        if IsDefined(service) {
            service.RequestPage(url);
        } else {
            this.ShowMessage("Cyberdeck service not running.");
        }
    }

    // Returns true when this browser was waiting for the page.
    public func OnPageReady(url: String) -> Bool {
        if !Equals(url, this.m_requested) {
            return false;
        }
        let service = DeckService.Get();
        if !IsDefined(service) {
            return false;
        }
        this.m_blocks = service.GetPageBlocks(url);
        this.m_url = service.GetPageCanonical(url);
        this.m_title = service.GetPageTitle(url);
        this.m_theme = StringToName(service.GetPageTheme(url));
        this.m_requested = "";
        this.m_address.SetText(this.m_url);
        this.m_tabText.SetText(RNShorten(this.m_title, 30));
        this.m_tabAccent.BindProperty(n"tintColor", this.m_theme);
        this.m_lock.SetText(StrBeginsWith(this.m_url, "net://") ? "NET" : (StrBeginsWith(this.m_url, "market://") ? "NCSE" : "NC//NET"));
        this.BuildUnits();
        this.Render();
        this.SetStatus("Done");
        return true;
    }

    private func SetStatus(text: String) {
        if IsDefined(this.m_status) {
            this.m_status.SetText(text);
        }
    }

    private func ShowMessage(text: String) {
        let content = this.m_content;
        if !IsDefined(content) {
            return;
        }
        content.RemoveAllChildren();
        let message = RNText(n"message", 26, n"MainColors.Red");
        message.SetText(text);
        message.Reparent(content);
    }

    // --- scrolling ----------------------------------------------------------------

    // Groups blocks into the units that are drawn and scrolled together.
    private func BuildUnits() {
        ArrayClear(this.m_unitStart);
        ArrayClear(this.m_unitEnd);
        let count = ArraySize(this.m_blocks);
        let i = 0;
        while i < count {
            let kind = this.m_blocks[i].kind;
            let last = i;
            if kind == 2 || kind == 6 || kind == 12 {
                while last + 1 < count && this.m_blocks[last + 1].kind == kind {
                    last += 1;
                }
            }
            ArrayPush(this.m_unitStart, i);
            ArrayPush(this.m_unitEnd, last);
            i = last + 1;
        }
    }

    private func EstimateHeight(unit: Int32) -> Float {
        let block = this.m_blocks[this.m_unitStart[unit]];
        switch block.kind {
            case 1: return 140.0;
            case 2: return 62.0;
            case 3: return 56.0;
            case 4: return 12.0 + 34.0 * Cast<Float>(1 + StrLen(block.text) / 95);
            case 5: return 42.0;
            case 6: return 70.0;
            case 7: return StrLen(block.extra) > 0 ? 66.0 + 30.0 * Cast<Float>(1 + StrLen(block.extra) / 90) : 66.0;
            case 8: return 40.0;
            case 9: return 180.0;
            case 10: return 24.0;
            case 11: return 72.0;
            case 12: return 160.0;
            case 13: return 38.0;
            default: return 40.0;
        }
    }

    private func PageHeight() -> Float {
        let content = this.m_content;
        if IsDefined(content) {
            let measured = content.GetDesiredSize().Y;
            if measured > 1.0 {
                return measured;
            }
        }
        return this.m_estimate;
    }

    private func MaxOffset() -> Float {
        return MaxF(0.0, this.PageHeight() - this.ViewportHeight() + 40.0);
    }

    // One wheel notch moves the page by step * 45 pixels.
    public func Scroll(step: Int32) {
        this.ScrollTo(this.m_offset + 45.0 * Cast<Float>(step));
    }

    private func ScrollTo(offset: Float) {
        let content = this.m_content;
        if !IsDefined(content) {
            return;
        }
        this.m_offset = MinF(MaxF(0.0, offset), this.MaxOffset());
        content.SetTranslation(Vector2(0.0, -this.m_offset));
        this.UpdateScrollbar();
    }

    // Is a screen position over the page area? Used for mouse wheel scrolling.
    public func Contains(screenPosition: Vector2) -> Bool {
        let root = this.m_root;
        if !IsDefined(root) || !root.IsVisible() {
            return false;
        }
        let local = WidgetUtils.GlobalToLocal(root, screenPosition);
        return local.X >= 0.0 && local.X <= 1320.0 && local.Y >= this.ContentTop() && local.Y <= this.ContentBottom();
    }

    // --- drawing ------------------------------------------------------------------

    private func Render() {
        let content = this.m_content;
        if !IsDefined(content) {
            return;
        }
        content.RemoveAllChildren();
        this.m_estimate = 0.0;
        let units = ArraySize(this.m_unitStart);
        if units == 0 {
            this.ShowMessage("This page is empty.");
        }
        let unit = 0;
        while unit < units && unit < 250 {
            this.DrawUnit(content, unit);
            this.m_estimate += this.EstimateHeight(unit);
            unit += 1;
        }
        this.m_offset = 0.0;
        content.SetTranslation(Vector2(0.0, 0.0));
        this.UpdateScrollbar();
    }

    private func UpdateScrollbar() {
        let thumb = this.m_thumb;
        if !IsDefined(thumb) {
            return;
        }
        let track = this.ContentBottom() - this.ContentTop() - 16.0;
        let page = this.PageHeight();
        let view = this.ViewportHeight();
        if page <= view {
            thumb.SetVisible(false);
            return;
        }
        thumb.SetVisible(true);
        let size = MaxF(40.0, track * view / page);
        let maxOffset = MaxF(1.0, this.MaxOffset());
        let top = (track - size) * MinF(1.0, this.m_offset / maxOffset);
        thumb.SetSize(8.0, size);
        thumb.SetMargin(inkMargin(0.0, 8.0 + top, 10.0, 0.0));
        thumb.BindProperty(n"tintColor", this.m_theme);
    }

    private func ColorOf(block: ref<RNPageBlock>, fallback: CName) -> CName {
        return StrLen(block.color) > 0 ? StringToName(block.color) : fallback;
    }

    // Makes a widget clickable as block number index.
    private func Clickable(widget: ref<inkWidget>, index: Int32) {
        widget.SetName(StringToName("blk" + IntToString(index)));
        widget.SetInteractive(true);
        widget.RegisterToCallback(n"OnRelease", this, n"OnBlockClick");
        widget.RegisterToCallback(n"OnHoverOver", this, n"OnBlockHover");
        widget.RegisterToCallback(n"OnHoverOut", this, n"OnBlockLeave");
        this.Hover(widget);
    }

    private func DrawUnit(content: ref<inkVerticalPanel>, unit: Int32) {
        let first = this.m_unitStart[unit];
        let last = this.m_unitEnd[unit];
        let block = this.m_blocks[first];
        let width = this.ContentWidth();

        switch block.kind {
            case 1: this.DrawBanner(content, block, width); break;
            case 2: this.DrawNav(content, first, last); break;
            case 3: this.DrawHeading(content, block); break;
            case 4: this.DrawText(content, block, width); break;
            case 5: this.DrawLink(content, block, first); break;
            case 6: this.DrawButtons(content, first, last); break;
            case 7: this.DrawCard(content, block, first, width); break;
            case 8: this.DrawRow(content, block, first, width); break;
            case 9: this.DrawChart(content, block, width); break;
            case 10: this.DrawDivider(content, width); break;
            case 11: this.DrawNotice(content, block, width); break;
            case 12: this.DrawIcons(content, first, last); break;
            case 13: this.DrawField(content, block); break;
            default: break;
        }
    }

    private func DrawHeading(content: ref<inkVerticalPanel>, block: ref<RNPageBlock>) {
        let heading = RNText(n"heading", 34, this.ColorOf(block, n"MainColors.Red"));
        heading.SetMargin(inkMargin(0.0, 14.0, 0.0, 6.0));
        heading.SetText(block.text);
        heading.Reparent(content);
    }

    private func DrawText(content: ref<inkVerticalPanel>, block: ref<RNPageBlock>, width: Float) {
        let paragraph = RNText(n"text", 24, this.ColorOf(block, n"MainColors.Blue"));
        paragraph.SetMargin(inkMargin(0.0, 4.0, 0.0, 8.0));
        paragraph.SetWrappingAtPosition(width);
        paragraph.SetText(block.text);
        paragraph.Reparent(content);
    }

    private func DrawLink(content: ref<inkVerticalPanel>, block: ref<RNPageBlock>, index: Int32) {
        let link = RNText(n"link", 25, n"MainColors.ActiveBlue");
        link.SetMargin(inkMargin(0.0, 4.0, 0.0, 6.0));
        link.SetText("> " + block.text);
        link.Reparent(content);
        this.Clickable(link, index);
    }

    private func DrawDivider(content: ref<inkVerticalPanel>, width: Float) {
        let rule = RNRect(n"divider", RNColor(0.8, 0.15, 0.15, 0.5));
        rule.SetAnchor(inkEAnchor.TopLeft);
        rule.SetSize(width, 2.0);
        rule.SetMargin(inkMargin(0.0, 10.0, 0.0, 10.0));
        rule.Reparent(content);
    }

    private func DrawBanner(content: ref<inkVerticalPanel>, block: ref<RNPageBlock>, width: Float) {
        let color = this.ColorOf(block, this.m_theme);
        let banner = new inkCanvas();
        banner.SetName(n"banner");
        banner.SetSize(width, 124.0);
        banner.SetMargin(inkMargin(0.0, 0.0, 0.0, 16.0));
        banner.Reparent(content);
        RNImage(n"bg", RNShapes(), n"button_big2_bg", color, 0.25).Reparent(banner);
        RNImage(n"frame", RNShapes(), n"button_big2_fg", color, 0.9).Reparent(banner);
        let name = RNText(n"name", 56, color);
        name.SetMargin(inkMargin(32.0, 12.0, 0.0, 0.0));
        name.SetText(block.text);
        name.Reparent(banner);
        let tagline = RNText(n"tagline", 24, n"MainColors.Yellow");
        tagline.SetMargin(inkMargin(34.0, 80.0, 0.0, 0.0));
        tagline.SetText(block.extra);
        tagline.Reparent(banner);
    }

    private func DrawNav(content: ref<inkVerticalPanel>, first: Int32, last: Int32) {
        let wrapper = new inkVerticalPanel();
        wrapper.SetName(n"nav");
        wrapper.SetMargin(inkMargin(0.0, 0.0, 0.0, 12.0));
        wrapper.Reparent(content);
        let bar = new inkHorizontalPanel();
        bar.SetName(n"items");
        bar.Reparent(wrapper);
        let i = first;
        while i <= last {
            let item = RNText(n"item", 26, n"MainColors.ActiveBlue");
            item.SetMargin(inkMargin(0.0, 0.0, 44.0, 6.0));
            item.SetText(StrUpper(this.m_blocks[i].text));
            item.Reparent(bar);
            this.Clickable(item, i);
            i += 1;
        }
        let rule = RNRect(n"rule", RNColor(0.8, 0.15, 0.15, 0.4));
        rule.SetAnchor(inkEAnchor.TopLeft);
        rule.SetSize(this.ContentWidth(), 2.0);
        rule.Reparent(wrapper);
    }

    private func DrawButtons(content: ref<inkVerticalPanel>, first: Int32, last: Int32) {
        let row = new inkHorizontalPanel();
        row.SetName(n"buttons");
        row.SetMargin(inkMargin(0.0, 6.0, 0.0, 10.0));
        row.Reparent(content);
        let i = first;
        while i <= last {
            let block = this.m_blocks[i];
            let color = this.ColorOf(block, this.m_theme);
            let button = new inkCanvas();
            button.SetSize(60.0 + 15.0 * Cast<Float>(StrLen(block.text)), 52.0);
            button.SetMargin(inkMargin(0.0, 0.0, 14.0, 0.0));
            button.Reparent(row);
            RNImage(n"bg", RNShapes(), n"button_big2_bg", color, 0.35).Reparent(button);
            RNImage(n"frame", RNShapes(), n"button_big2_fg", color, 1.0).Reparent(button);
            let text = RNText(n"label", 26, color);
            text.SetAnchor(inkEAnchor.Centered);
            text.SetAnchorPoint(Vector2(0.5, 0.5));
            text.SetHAlign(inkEHorizontalAlign.Center);
            text.SetText(StrUpper(block.text));
            text.Reparent(button);
            this.Clickable(button, i);
            i += 1;
        }
    }

    private func DrawCard(content: ref<inkVerticalPanel>, block: ref<RNPageBlock>, index: Int32, width: Float) {
        let color = this.ColorOf(block, this.m_theme);
        let height = StrLen(block.extra) > 0 ? 56.0 + 30.0 * Cast<Float>(1 + StrLen(block.extra) / 90) : 56.0;
        let card = new inkCanvas();
        card.SetName(n"card");
        card.SetSize(width, height);
        card.SetMargin(inkMargin(0.0, 0.0, 0.0, 10.0));
        card.Reparent(content);
        RNImage(n"bg", RNShapes(), n"cell_bg", n"MainColors.Fullscreen_PrimaryBackgroundDarkest", 0.95).Reparent(card);
        RNImage(n"frame", RNShapes(), n"cell_fg", color, 0.5).Reparent(card);
        let accent = new inkRectangle();
        accent.SetName(n"accent");
        accent.SetSize(6.0, height - 16.0);
        accent.SetMargin(inkMargin(10.0, 8.0, 0.0, 0.0));
        accent.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
        accent.BindProperty(n"tintColor", color);
        accent.Reparent(card);
        let body = new inkVerticalPanel();
        body.SetName(n"body");
        body.SetMargin(inkMargin(30.0, 12.0, 20.0, 0.0));
        body.Reparent(card);
        let title = RNText(n"title", 27, color);
        title.SetWrappingAtPosition(width - 60.0);
        title.SetText(block.text);
        title.Reparent(body);
        if StrLen(block.extra) > 0 {
            let text = RNText(n"text", 23, n"MainColors.Blue");
            text.SetMargin(inkMargin(0.0, 4.0, 0.0, 0.0));
            text.SetWrappingAtPosition(width - 60.0);
            text.SetText(block.extra);
            text.Reparent(body);
        }
        if StrLen(block.link) > 0 {
            this.Clickable(card, index);
        }
    }

    private func ColumnWidth(column: Int32) -> Float {
        switch column {
            case 0: return 150.0;
            case 1: return 440.0;
            case 2: return 260.0;
            default: return 370.0;
        }
    }

    private func DrawRow(content: ref<inkVerticalPanel>, block: ref<RNPageBlock>, index: Int32, width: Float) {
        let color = this.ColorOf(block, n"MainColors.Blue");
        let row = new inkCanvas();
        row.SetName(n"row");
        row.SetSize(width, 36.0);
        row.SetMargin(inkMargin(0.0, 0.0, 0.0, 4.0));
        row.Reparent(content);
        let stripe = RNRect(n"bg", RNColor(0.06, 0.07, 0.11, 0.9));
        stripe.Reparent(row);
        let columns = new inkHorizontalPanel();
        columns.SetName(n"columns");
        columns.SetMargin(inkMargin(12.0, 4.0, 0.0, 0.0));
        columns.Reparent(row);
        let parts = StrSplit(block.text, "|", true);
        let i = 0;
        while i < ArraySize(parts) {
            let cell = new inkCanvas();
            cell.SetSize(this.ColumnWidth(i), 30.0);
            cell.Reparent(columns);
            let text = RNText(n"cell", 24, i == 0 ? color : (i == ArraySize(parts) - 1 ? color : n"MainColors.Blue"));
            text.SetText(RNShorten(parts[i], Cast<Int32>(this.ColumnWidth(i) / 13.0)));
            text.Reparent(cell);
            i += 1;
        }
        if StrLen(block.link) > 0 {
            this.Clickable(row, index);
        }
    }

    private func DrawChart(content: ref<inkVerticalPanel>, block: ref<RNPageBlock>, width: Float) {
        let color = this.ColorOf(block, this.m_theme);
        let values = StrSplit(block.extra, ",", false);
        let chart = new inkCanvas();
        chart.SetName(n"chart");
        chart.SetSize(width, 170.0);
        chart.SetMargin(inkMargin(0.0, 4.0, 0.0, 10.0));
        chart.Reparent(content);
        RNImage(n"bg", RNShapes(), n"cell_bg", n"MainColors.Fullscreen_PrimaryBackgroundDarkest", 0.95).Reparent(chart);
        RNImage(n"frame", RNShapes(), n"cell_fg", color, 0.4).Reparent(chart);
        let count = ArraySize(values);
        if count < 2 {
            let empty = RNText(n"empty", 24, n"MainColors.Yellow");
            empty.SetMargin(inkMargin(24.0, 70.0, 0.0, 0.0));
            empty.SetText("Not enough trading history yet.");
            empty.Reparent(chart);
            return;
        }
        let low = 1000000000.0;
        let high = -1000000000.0;
        for value in values {
            let v = StringToFloat(value);
            low = MinF(low, v);
            high = MaxF(high, v);
        }
        let bars = new inkHorizontalPanel();
        bars.SetName(n"bars");
        bars.SetMargin(inkMargin(20.0, 14.0, 20.0, 0.0));
        bars.Reparent(chart);
        let barWidth = MaxF(4.0, (width - 40.0) / Cast<Float>(count) - 4.0);
        for value in values {
            let v = StringToFloat(value);
            let height = high > low ? 14.0 + (v - low) / (high - low) * 126.0 : 70.0;
            let slot = new inkCanvas();
            slot.SetSize(barWidth + 4.0, 142.0);
            slot.Reparent(bars);
            let bar = new inkRectangle();
            bar.SetAnchor(inkEAnchor.BottomLeft);
            bar.SetAnchorPoint(Vector2(0.0, 1.0));
            bar.SetSize(barWidth, height);
            bar.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
            bar.BindProperty(n"tintColor", color);
            bar.SetOpacity(0.85);
            bar.Reparent(slot);
        }
    }

    private func DrawNotice(content: ref<inkVerticalPanel>, block: ref<RNPageBlock>, width: Float) {
        let color = this.ColorOf(block, n"MainColors.Yellow");
        let notice = new inkCanvas();
        notice.SetName(n"notice");
        notice.SetSize(width, 60.0);
        notice.SetMargin(inkMargin(0.0, 4.0, 0.0, 10.0));
        notice.Reparent(content);
        RNImage(n"bg", RNShapes(), n"cell_bg", color, 0.2).Reparent(notice);
        RNImage(n"frame", RNShapes(), n"cell_fg", color, 0.9).Reparent(notice);
        let text = RNText(n"text", 25, color);
        text.SetAnchor(inkEAnchor.CenterLeft);
        text.SetAnchorPoint(Vector2(0.0, 0.5));
        text.SetMargin(inkMargin(24.0, 0.0, 0.0, 0.0));
        text.SetText(RNShorten(block.text, 92));
        text.Reparent(notice);
    }

    private func DrawIcons(content: ref<inkVerticalPanel>, first: Int32, last: Int32) {
        let row = new inkHorizontalPanel();
        row.SetName(n"icons");
        row.SetMargin(inkMargin(0.0, 6.0, 0.0, 12.0));
        row.Reparent(content);
        let i = first;
        while i <= last {
            let block = this.m_blocks[i];
            let tile = new inkCanvas();
            tile.SetSize(170.0, 140.0);
            tile.SetMargin(inkMargin(0.0, 0.0, 18.0, 0.0));
            tile.Reparent(row);
            RNImage(n"bg", RNShapes(), n"cell_bg", n"MainColors.Fullscreen_PrimaryBackgroundDarkest", 0.95).Reparent(tile);
            RNImage(n"frame", RNShapes(), n"cell_fg", this.m_theme, 0.6).Reparent(tile);
            let icon = RNIcon(n"icon", StringToName(block.extra), 64.0, n"MainColors.Blue");
            icon.SetAnchor(inkEAnchor.TopCenter);
            icon.SetAnchorPoint(Vector2(0.5, 0.0));
            icon.SetMargin(inkMargin(0.0, 16.0, 0.0, 0.0));
            icon.Reparent(tile);
            let label = RNText(n"label", 23, n"MainColors.Blue");
            label.SetAnchor(inkEAnchor.BottomCenter);
            label.SetAnchorPoint(Vector2(0.5, 1.0));
            label.SetHAlign(inkEHorizontalAlign.Center);
            label.SetMargin(inkMargin(0.0, 0.0, 0.0, 14.0));
            label.SetText(block.text);
            label.Reparent(tile);
            if StrLen(block.link) > 0 {
                this.Clickable(tile, i);
            }
            i += 1;
        }
    }

    private func DrawField(content: ref<inkVerticalPanel>, block: ref<RNPageBlock>) {
        let row = new inkHorizontalPanel();
        row.SetName(n"field");
        row.SetMargin(inkMargin(0.0, 2.0, 0.0, 6.0));
        row.Reparent(content);
        let labelBox = new inkCanvas();
        labelBox.SetSize(260.0, 30.0);
        labelBox.Reparent(row);
        let label = RNText(n"label", 24, n"MainColors.Yellow");
        label.SetText(StrUpper(block.text));
        label.Reparent(labelBox);
        let value = RNText(n"value", 24, this.ColorOf(block, n"MainColors.Blue"));
        value.SetText(block.extra);
        value.Reparent(row);
    }

    // --- input ----------------------------------------------------------------

    private func BlockAt(e: ref<inkPointerEvent>) -> Int32 {
        let index = RNNameNumber(e.GetCurrentTarget().GetName(), "blk");
        return index >= 0 && index < ArraySize(this.m_blocks) ? index : -1;
    }

    protected cb func OnBlockClick(e: ref<inkPointerEvent>) -> Bool {
        if !e.IsAction(n"click") {
            return false;
        }
        let index = this.BlockAt(e);
        if index >= 0 {
            let link = this.m_blocks[index].link;
            if StrLen(link) > 0 {
                this.Navigate(link, true);
            }
        }
        return false;
    }

    protected cb func OnBlockHover(e: ref<inkPointerEvent>) -> Bool {
        let index = this.BlockAt(e);
        if index >= 0 {
            this.SetStatus(this.m_blocks[index].link);
        }
        return false;
    }

    protected cb func OnBlockLeave(e: ref<inkPointerEvent>) -> Bool {
        this.SetStatus(StrLen(this.m_requested) > 0 ? "Connecting..." : "Done");
        return false;
    }

    protected cb func OnAddressKey(event: ref<inkKeyInputEvent>) -> Bool {
        if Equals(event.GetAction(), EInputAction.IACT_Press) && Equals(event.GetKey(), EInputKey.IK_Enter) {
            this.Navigate(this.m_address.GetText(), true);
        }
        return false;
    }

    protected cb func OnBack(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") && ArraySize(this.m_back) > 0 {
            let last = ArraySize(this.m_back) - 1;
            let url = this.m_back[last];
            ArrayErase(this.m_back, last);
            ArrayPush(this.m_forward, this.m_url);
            this.Navigate(url, false);
        }
        return false;
    }

    protected cb func OnForward(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") && ArraySize(this.m_forward) > 0 {
            let last = ArraySize(this.m_forward) - 1;
            let url = this.m_forward[last];
            ArrayErase(this.m_forward, last);
            ArrayPush(this.m_back, this.m_url);
            this.Navigate(url, false);
        }
        return false;
    }

    protected cb func OnReload(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") {
            this.Navigate(this.m_url, false);
        }
        return false;
    }

    protected cb func OnHome(e: ref<inkPointerEvent>) -> Bool {
        if e.IsAction(n"click") {
            this.Navigate("nc://home", true);
        }
        return false;
    }
}
