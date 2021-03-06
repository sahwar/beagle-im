//
// ChatsListView.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see https://www.gnu.org/licenses/.
//

import AppKit
import TigaseSwift

class AbstractChatItem: ChatItemProtocol {
    
    let chat: DBChatProtocol;
    
    var name: String;
    var lastActivity: LastChatActivity? {
        return chat.lastActivity;
    }
    var lastMessageTs: Date {
        return chat.timestamp;
    }
    var unread: Int {
        return chat.unread;
    }
    
    init(chat: DBChatProtocol, name: String) {
        self.chat = chat;
        self.name = name;
    }
}

class ChatItem: AbstractChatItem {
    
    let isInRoster: Bool;
    
    init(chat: DBChatProtocol) {
        if let sessionObject = XmppService.instance.getClient(for: chat.account)?.sessionObject {
            let rosterItem = RosterModule.getRosterStore(sessionObject).get(for: chat.jid);
            isInRoster = rosterItem != nil;
            super.init(chat: chat, name: rosterItem?.name ?? chat.jid.stringValue);
        } else {
            isInRoster = true;
            super.init(chat: chat, name: chat.jid.stringValue);
        }
    }
}

class GroupchatItem: AbstractChatItem {

    init(chat: DBChatProtocol) {
        super.init(chat: chat, name: (chat as? DBChatStore.DBRoom)?.name ?? chat.jid.stringValue);
    }
    
}

protocol ChatsListViewDataSourceDelegate: class {
    
    func itemsInserted(at: IndexSet, inParent: Any?);
    
    func itemsRemoved(at: IndexSet, inParent: Any?);
    
    func itemChanged(item: Any?);
    
    func itemMoved(from: Int, fromParent: Any?, to: Int, toParent: Any?);
    
    func reload();
}

class ChatsListViewController: NSViewController, NSOutlineViewDataSource, ChatsListViewDataSourceDelegate {
    
    static let CHAT_SELECTED = Notification.Name("chatSelected");
    static let CLOSE_SELECTED_CHAT = Notification.Name("chatSelectedClose");
    
    @IBOutlet var outlineView: ChatsListView!;
    
    var groups: [ChatsListGroupProtocol] = [];

    override func viewDidLoad() {
        self.groups = [ChatsListGroupGroupchat(delegate: self), ChatsListGroupChat(delegate: self), ChatsListGroupChatUnknown(delegate: self)];
        outlineView.reloadData();
//        outlineView.expandItem(nil, expandChildren: true);
        
        NotificationCenter.default.addObserver(self, selector: #selector(chatSelected), name: ChatsListViewController.CHAT_SELECTED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(closeSelectedChat), name: ChatsListViewController.CLOSE_SELECTED_CHAT, object: nil);
        
        NotificationCenter.default.addObserver(self, selector: #selector(hourChanged), name: AppDelegate.HOUR_CHANGED, object: nil);
    }
    
    override func viewWillAppear() {
//        self.view.window!.acceptsMouseMovedEvents = true;
        super.viewWillAppear();
        outlineView.expandItem(nil, expandChildren: true);
        self.view.layer?.backgroundColor = NSColor(named: "sidebarBackgroundColor")!.cgColor;
    }
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let group = item as? ChatsListGroupProtocol {
            return group.count;
        }
        return groups.count;
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let group = item as? ChatsListGroupProtocol {
            return group.getChat(at: index)!;
        }
        return groups[index];
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard item is ChatsListGroupProtocol else {
            return false;
        }
        return true;
    }
    
    func reload() {
        outlineView.reloadData();
    }
    
    func itemsInserted(at: IndexSet, inParent: Any?) {
        outlineView.insertItems(at: at, inParent: inParent, withAnimation: .slideLeft);
    }
    
    func itemsRemoved(at: IndexSet, inParent: Any?) {
        outlineView.removeItems(at: at, inParent: inParent, withAnimation: .slideRight);
    }
    
    func itemMoved(from: Int, fromParent: Any?, to: Int, toParent: Any?) {
        outlineView.moveItem(at: from, inParent: fromParent, to: to, inParent: toParent);
    }
    
    func itemChanged(item: Any?) {
        outlineView.reloadItem(item);
    }
    
    @IBAction func openNewChatClicked(_ sender: NSButton) {
        print("open new chat cliecked");
        guard let group = (sender as? OutlineGroupItemButton)?.group else {
            return;
        }
        
        print("clicked button for", group.name);
        
        if groups.firstIndex(where: { it -> Bool in return it.name == group.name}) == 0 {
            guard let windowController = storyboard?.instantiateController(withIdentifier: "OpenGroupchatController") as? NSWindowController else {
                return;
            }
            view.window?.beginSheet(windowController.window!, completionHandler: nil);
        } else {
            guard let windowController = storyboard?.instantiateController(withIdentifier: "Open1On1ChatController") as? NSWindowController else {
                return;
            }
            view.window?.beginSheet(windowController.window!, completionHandler: nil);
        }
    }
    
    @objc func closeSelectedChat(_ notification: Notification) {
        print("closing chats for: \(self.outlineView.selectedRowIndexes)");
        let toClose = self.outlineView.selectedRowIndexes;
        toClose.forEach { (row) in
            guard let item = self.outlineView.item(atRow: row) as? ChatItemProtocol else {
                return;
            }
            
            self.close(chat: item);
        }
    }
    
    private var scrollChatToMessageWithId: Int?;
    
    @objc func chatSelected(_ notification: Notification) {
        let messageId = notification.userInfo?["messageId"] as? Int;
        guard let chat = notification.object as? DBChatProtocol else {
            guard let account = notification.userInfo?["account"] as? BareJID, let jid = notification.userInfo?["jid"] as? BareJID else {
                self.outlineView.selectRowIndexes(IndexSet(), byExtendingSelection: false);
                return;
            }
            self.groups.forEach { group in
                group.forChat(account: account, jid: jid) { item in
                    DispatchQueue.main.async {
                        let row = self.outlineView.row(forItem: item);
                        guard row >= 0 else {
                            return;
                        }
                        self.view.window?.windowController?.showWindow(self);
                        self.scrollChatToMessageWithId = messageId;
                        self.outlineView.selectRowIndexes(IndexSet(), byExtendingSelection: false);
                        self.outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false);
                    }
                }
            }
            return;
        }

        self.groups.forEach { group in
            group.forChat(chat) { item in
                DispatchQueue.main.async {
                    let row = self.outlineView.row(forItem: item);
                    guard row >= 0 else {
                        return;
                    }
                    self.view.window?.windowController?.showWindow(self);
                    self.scrollChatToMessageWithId = messageId;
                    self.outlineView.selectRowIndexes(IndexSet(), byExtendingSelection: false);
                    self.outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false);
                }
            }
        }
    }

    @objc func hourChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            for i in 0..<self.outlineView.numberOfRows {
                if let item = self.outlineView.item(atRow: i) {
                    self.itemChanged(item: item);
                }
            }
        }
    }
    
}

extension ChatsListViewController: NSOutlineViewDelegate {
    
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if item is ChatsListGroupProtocol {
            if outlineView.isItemExpanded(item) {
                //                outlineView.collapseItem(item);
            } else {
                outlineView.expandItem(item);
            }
            return false;
        }
        if item is ChatItem {
            return true;
        }
        if item is GroupchatItem {
            return true;
        }
        return false;
    }
    
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        return item is ChatsListGroupProtocol;
    }
    
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        return ChatsListTableRowView(frame: NSRect.zero);
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        if self.outlineView.selectedRowIndexes.count <= 1 {
            self.outlineView.selectionDirection = .unknown;
        }
        
        let selected = self.outlineView.selectedRow;
        print("selected row:", selected);
        let item = self.outlineView.selectedRowIndexes.count == 1 ? self.outlineView.item(atRow: selected) : nil;
        if let splitController = self.outlineView.window?.contentViewController as? NSSplitViewController {
            if let chat = item as? ChatItem {
                print("selected chat item:", chat.name);
                let chatController = self.storyboard!.instantiateController(withIdentifier: "ChatViewController") as! ChatViewController;
                chatController.chat = chat.chat;
                chatController.scrollChatToMessageWithId = self.scrollChatToMessageWithId;
                self.scrollChatToMessageWithId = nil;
                let item = NSSplitViewItem(viewController: chatController);
                if splitController.splitViewItems.count == 1 {
                    splitController.addSplitViewItem(item);
                } else {
                    splitController.removeSplitViewItem(splitController.splitViewItems[1]);
                    splitController.addSplitViewItem(item);
                }
            } else if let room = item as? GroupchatItem {
                let roomController = self.storyboard?.instantiateController(withIdentifier: "GroupchatViewController") as! GroupchatViewController;
                roomController.room = (room.chat as! DBChatStore.DBRoom);
                roomController.scrollChatToMessageWithId = self.scrollChatToMessageWithId;
                self.scrollChatToMessageWithId = nil;
                let item = NSSplitViewItem(viewController: roomController);
                if splitController.splitViewItems.count == 1 {
                    splitController.addSplitViewItem(item);
                } else {
                    splitController.removeSplitViewItem(splitController.splitViewItems[1]);
                    splitController.addSplitViewItem(item);
                }
            } else if item == nil {
                let controller = self.storyboard!.instantiateController(withIdentifier: "EmptyViewController") as! NSViewController;
                if splitController.splitViewItems.count > 1 {
                    splitController.removeSplitViewItem(splitController.splitViewItems[1]);
                }
                splitController.addSplitViewItem(NSSplitViewItem(viewController: controller));
            }
        }
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        //var view: NSTableCellView?
//        guard tableColumn?.identifier.rawValue == "ITEM1" else {
//            return nil;
//        }
        
        if let group = item as? ChatsListGroupProtocol {
            let view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("ChatGroupCell"), owner: self) as? NSTableCellView;
            if let textField = view?.textField {
                textField.stringValue = group.name;
                //textField.sizeToFit();
            }
            if let button = view?.subviews[1] as? OutlineGroupItemButton {
                button.group = group;
                button.isHidden = !group.canOpenChat;
            }
            return view;
        } else if let chat = item as? ChatItemProtocol {
            let view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("ChatCell"), owner: self) as? ChatCellView;
            view?.avatar.backgroundColor = NSColor(named: "sidebarBackgroundColor");
            view?.update(from: chat);
//            view?.lastMessage.preferredMaxLayoutWidth = self.outlineView.outlineTableColumn!.width - 66;
            view?.closeFunction = {
                self.close(chat: chat);
            }
            view?.setMouseHovers(false);
            view?.layout();
            return view;
        }
        return nil;
    }
        
    func close(chat: ChatItemProtocol) {
        switch chat.chat {
        case let c as DBChatStore.DBChat:
            guard let messageModule: MessageModule = XmppService.instance.getClient(for: c.account)?.modulesManager.getModule(MessageModule.ID) else {
                return;
            }
            _ = messageModule.chatManager.close(chat: c);
        case let r as DBChatStore.DBRoom:
            guard let mucModule: MucModule = XmppService.instance.getClient(for: r.account)?.modulesManager.getModule(MucModule.ID) else {
                return;
            }
            
            if r.presences[r.nickname]?.affiliation == .owner {
                let alert = NSAlert();
                alert.alertStyle = .warning;
                alert.messageText = "Delete group chat?"
                alert.informativeText = "You are leaving the group chat \(r.name ?? r.jid.bareJid.stringValue)";
                alert.addButton(withTitle: "Delete chat")
                alert.addButton(withTitle: "Leave chat")
                alert.beginSheetModal(for: self.view.window!) { (response) in
                    if (response == .alertFirstButtonReturn) {
                        mucModule.destroy(room: r);
                        PEPBookmarksModule.remove(from: r.account, bookmark: Bookmarks.Conference(name: r.name ?? r.roomJid.stringValue, jid: r.jid, autojoin: false));
                    } else {
                        mucModule.leave(room: r);
                        PEPBookmarksModule.remove(from: r.account, bookmark: Bookmarks.Conference(name: r.name ?? r.roomJid.stringValue, jid: r.jid, autojoin: false));
                    }
                };
            } else {
                mucModule.leave(room: r);
                PEPBookmarksModule.remove(from: r.account, bookmark: Bookmarks.Conference(name: r.name ?? r.roomJid.stringValue, jid: r.jid, autojoin: false));
            }
        default:
            print("unknown type of chat!");
        }
    }
}

class ChatsListView: NSOutlineView {
    
    var trackingArea: NSTrackingArea?;
    var mouseOverRow = -1;
    var mouseInside = false;
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect);
        trackingArea = NSTrackingArea(rect: self.frame, options: [.mouseEnteredAndExited,.mouseMoved,.activeAlways], owner: self, userInfo: nil);
        self.addTrackingArea(trackingArea!);
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { (event) -> NSEvent? in
            guard event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.first?.unicodeScalars.first?.value == UInt32(NSBackspaceCharacter) else {
                return event;
            }
            
            // we detected shortcut!!
            return nil;
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
    }
    
    override func awakeFromNib() {
        super.awakeFromNib();
    }
    
    deinit {
    }
    
    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        return NSRect.zero;
    }
    
    override func mouseEntered(with event: NSEvent) {
        print("mouse entered");
        mouseInside = true;
        updateMouseOver(from: event);
    }
    
    override func mouseExited(with event: NSEvent) {
        print("mouse exited");
        mouseInside = false;
        updateMouseOver(from: event);
    }
    
    override func mouseMoved(with event: NSEvent) {
        guard mouseInside else {
            return;
        }

        updateMouseOver(from: event);
    }
    
    enum SelectionDirection {
        case up
        case down
        case unknown
    }
    
    var selectionDirection: SelectionDirection = .unknown;
    
    override func keyDown(with event: NSEvent) {
        print("got event: \(event)");
        
        let sorted = selectedRowIndexes.sorted();
        guard !sorted.isEmpty else {
            super.keyDown(with: event);
            return;
        }
        
        let first = sorted.first!;
        let last = sorted.last!;
        
        let move = !event.modifierFlags.contains(.shift);
        
        switch Int(event.charactersIgnoringModifiers?.first?.unicodeScalars.first?.value ?? 0) {
        case NSDownArrowFunctionKey:
            switch selectionDirection {
            case .down, .unknown:
                selectionDirection = .down;
                let newLast = last.advanced(by: 1);
                guard newLast < numberOfRows else {
                    return;
                }
                
                if move {
                    self.updateRowSelection(IndexSet(integer: newLast), byExtendingSelection: false);
                } else {
                    self.updateRowSelection(IndexSet(integersIn: first...newLast), byExtendingSelection: false);
                }
            case .up:
                let newFirst = first.advanced(by: 1);
                guard newFirst <= last else {
                    self.selectionDirection = .unknown;
                    self.keyDown(with: event);
                    return;
                }
                if move {
                    self.updateRowSelection(IndexSet(integer: newFirst), byExtendingSelection: false);
                } else {
                    self.updateRowSelection(IndexSet(integersIn: newFirst...last), byExtendingSelection: false);
                }
            }
        case NSUpArrowFunctionKey:
            switch selectionDirection {
            case .down:
                let newLast = last.advanced(by: -1);
                guard newLast >= first else {
                    selectionDirection = .unknown;
                    self.keyDown(with: event);
                    return;
                }
                if move {
                    self.updateRowSelection(IndexSet(integer: newLast), byExtendingSelection: false);
                } else {
                    self.updateRowSelection(IndexSet(integersIn: first...newLast), byExtendingSelection: false);
                }
            case .up, .unknown:
                selectionDirection = .up;
                let newFirst = first.advanced(by: -1);
                guard newFirst >= 0 else {
                    return;
                }
                if move {
                    self.updateRowSelection(IndexSet(integer: newFirst), byExtendingSelection: false);
                } else {
                    self.updateRowSelection(IndexSet(integersIn: newFirst...last), byExtendingSelection: false);
                }
            }
        default:
            break;
        }
    }
    
    override func insertItems(at indexes: IndexSet, inParent parent: Any?, withAnimation animationOptions: NSTableView.AnimationOptions = []) {
        super.insertItems(at: indexes, inParent: parent, withAnimation: animationOptions);
        updateMouseOver(at: NSEvent.mouseLocation);
    }
    
    override func removeItems(at indexes: IndexSet, inParent parent: Any?, withAnimation animationOptions: NSTableView.AnimationOptions = []) {
        super.removeItems(at: indexes, inParent: parent, withAnimation: animationOptions);
        updateMouseOver(at: NSEvent.mouseLocation);
    }
    
    override func moveItem(at fromIndex: Int, inParent oldParent: Any?, to toIndex: Int, inParent newParent: Any?) {
        super.moveItem(at: fromIndex, inParent: oldParent, to: toIndex, inParent: newParent);
        updateMouseOver(at: NSEvent.mouseLocation);
    }
    
    fileprivate func updateMouseOver(from event: NSEvent) {
        updateMouseOver(at: event.locationInWindow);
    }
    
    fileprivate func updateMouseOver(at point: NSPoint, force: Bool = false) {
        let prevMouseOverRow = self.mouseOverRow;
        self.mouseOverRow = self.row(at: self.convert(point, from: nil));
        guard mouseOverRow != prevMouseOverRow else {
            return;
        }
        if prevMouseOverRow >= 0 {
            if prevMouseOverRow < self.numberOfRows {
                if let chatView = self.rowView(atRow: prevMouseOverRow, makeIfNecessary: false)?.subviews.last as? ChatCellView {
                    chatView.setMouseHovers(false);
                }
            }
        }
        if mouseOverRow >= 0 && mouseOverRow < self.numberOfRows {
            if let chatView = self.rowView(atRow: mouseOverRow, makeIfNecessary: false)?.subviews.last as? ChatCellView {
                chatView.setMouseHovers(true);
            }
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas();
        if trackingArea != nil {
            self.removeTrackingArea(trackingArea!);
        }
        self.trackingArea = NSTrackingArea(rect: self.frame, options: [.mouseEnteredAndExited,.mouseMoved,.activeAlways], owner: self, userInfo: nil);
        self.addTrackingArea(trackingArea!);
    }

    func updateRowSelection(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
        selectRowIndexes(indexes, byExtendingSelection: extend);
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self);
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        let selectedRow = self.selectedRow;
        if event.modifierFlags.contains(.shift) {
            if selectedRow != -1 {
                let endRow = self.row(at: self.convert(event.locationInWindow, from: nil));
                let range = selectedRow < endRow ? selectedRow...endRow : endRow...selectedRow;
            
                print("changing selection!");
                self.updateRowSelection(IndexSet(integersIn: range), byExtendingSelection: false);
                //NotificationCenter.default.post(name: NSOutlineView.selectionDidChangeNotification, object: nil);
            } else {
                let row = self.row(at: self.convert(event.locationInWindow, from: nil));

                print("changing selection!");
                if row != -1 {
                    self.updateRowSelection(IndexSet(integersIn: row...row), byExtendingSelection: false);
                }
                //NotificationCenter.default.post(name: NSOutlineView.selectionDidChangeNotification, object: nil);
            }
        } else {
            
            if let isKey = self.window?.isKeyWindow, !isKey {
                print("mouse down event!", event, self.window as Any, "list", NSApplication.shared.windows, "key:", self.window?.isKeyWindow as Any, "can:", self.window?.canBecomeKey as Any, "main:", self.window?.isMainWindow as Any, "can:", self.window?.canBecomeMain as Any, "isActive:", NSApp.isActive, "isRunning:", NSApp.isRunning, "isHidden:", NSApp.isHidden);
                NSApplication.shared.windows.forEach { (win) in
                    print("win:", win, "isMain:", win.isMainWindow, win.canBecomeMain, "isKey:", win.isKeyWindow, win.canBecomeKey, "sheet:", win.isSheet, "visible:", win.isVisible, "title:", win.title, "modal:", NSApp.modalWindow as Any)
                }
                
                NSApp.activate(ignoringOtherApps: true);
                self.window?.makeKey();
            }

            super.mouseDown(with: event);
        }
    }
    
}
