//
//  MPInspectorTabViewController.m
//  MacPass
//
//  Created by Michael Starke on 05.03.13.
//  Copyright (c) 2013 HicknHack Software GmbH. All rights reserved.
//

#import "MPInspectorViewController.h"
#import "MPIconHelper.h"
#import "MPEntryInspectorViewController.h"
#import "MPGroupInspectorViewController.h"
#import "MPDocument.h"
#import "MPNotifications.h"
#import "MPIconSelectViewController.h"

#import "NSDate+Humanized.h"
#import "KPKNode+IconImage.h"

#import "KPKTree.h"
#import "KPKMetaData.h"
#import "KPKGroup.h"
#import "KPKEntry.h"

#import "HNHGradientView.h"
#import "MPPopupImageView.h"

typedef NS_ENUM(NSUInteger, MPContentTab) {
  MPEntryTab,
  MPGroupTab,
  MPEmptyTab,
};

@interface MPInspectorViewController () {
  MPEntryInspectorViewController *_entryViewController;
  MPGroupInspectorViewController *_groupViewController;
  NSPopover *_popover;
  BOOL _isEditing;
}

@property (strong)  MPIconSelectViewController *iconSelectionViewController;

@property (nonatomic, strong) NSDate *modificationDate;
@property (nonatomic, strong) NSDate *creationDate;

@property (nonatomic, assign) NSUInteger activeTab;
@property (weak) IBOutlet NSTabView *tabView;
@property (weak) IBOutlet NSSplitView *splitView;
@property (weak) IBOutlet NSTextField *notesHeaderTextField;
@property (weak) IBOutlet HNHGradientView *notesHeaderGradientView;
@property (unsafe_unretained) IBOutlet NSTextView *notesTextView;

@end

@implementation MPInspectorViewController

- (id)init {
  return [[MPInspectorViewController alloc] initWithNibName:@"InspectorView" bundle:nil];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self) {
    _activeTab = MPEmptyTab;
    _entryViewController = [[MPEntryInspectorViewController alloc] init];
    _groupViewController = [[MPGroupInspectorViewController alloc] init];
    _isEditing = NO;
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSResponder *)reconmendedFirstResponder {
  return [self view];
}

#pragma mark Properties
- (void)setActiveTab:(NSUInteger)activeTab {
  if(_activeTab != activeTab) {
    _activeTab = activeTab;
  }
}

- (void)awakeFromNib {
  [self.bottomBar setBorderType:HNHBorderTop|HNHBorderHighlight];
  [self.notesHeaderGradientView setBorderType:HNHBorderBottom|HNHBorderHighlight];
  [[self.notesHeaderTextField cell] setBackgroundStyle:NSBackgroundStyleRaised];
  
  [[self.noSelectionInfo cell] setBackgroundStyle:NSBackgroundStyleRaised];
  [[self.itemImageView cell] setBackgroundStyle:NSBackgroundStyleRaised];
  [self.tabView bind:NSSelectedIndexBinding toObject:self withKeyPath:@"activeTab" options:nil];
  
  NSView *entryView = [_entryViewController view];
  NSView *groupView = [_groupViewController view];
  
  NSView *entryTabView = [[self.tabView tabViewItemAtIndex:MPEntryTab] view];
  [entryTabView addSubview:entryView];
  NSDictionary *views = NSDictionaryOfVariableBindings(entryView, groupView);
  [entryTabView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[entryView]|" options:0 metrics:nil views:views]];
  [entryTabView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[entryView]|" options:0 metrics:nil views:views]];
  
  NSView *groupTabView = [[self.tabView tabViewItemAtIndex:MPGroupTab] view];
  [groupTabView addSubview:groupView];
  [groupTabView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[groupView]|" options:0 metrics:nil views:views]];
  [groupTabView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[groupView]|" options:0 metrics:nil views:views]];
  
  [_groupViewController updateResponderChain];
  [_entryViewController updateResponderChain];
  
  [[self view] layout];
  [self _updateBindings:nil];
}

- (void)didLoadView {

}

- (void)regsiterNotificationsForDocument:(MPDocument *)document {
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_didChangeCurrentItem:)
                                               name:MPDocumentCurrentItemChangedNotification
                                             object:document];
  [_entryViewController setupBindings:document];
  [_groupViewController setupBindings:document];
  
}

- (void)setModificationDate:(NSDate *)modificationDate {
  _modificationDate = modificationDate;
  [self _updateDateStrings];
}

- (void)setCreationDate:(NSDate *)creationDate {
  _creationDate = creationDate;
  [self _updateDateStrings];
}

- (void)_updateDateStrings {
  
  if(!self.creationDate || !self.modificationDate ) {
    [self.modifiedTextField setStringValue:@""];
    [self.createdTextField setStringValue:@""];
    return; // No dates, just clear
  }
  
  NSString *creationString = [self.creationDate humanized];
  NSString *modificationString = [self.modificationDate humanized];
  
  NSString *modifedAtTemplate = NSLocalizedString(@"MODIFED_AT_%@", @"Modifed at template string. %@ is replaced by locaized date and time");
  NSString *createdAtTemplate = NSLocalizedString(@"CREATED_AT_%@", @"Created at template string. %@ is replaced by locaized date and time");
  
  [self.modifiedTextField setStringValue:[NSString stringWithFormat:modifedAtTemplate, modificationString]];
  [self.createdTextField setStringValue:[NSString stringWithFormat:createdAtTemplate, creationString]];
  
}

#pragma mark -
#pragma mark Click Edit Button
- (void)toggleEdit:(id)sender {
  BOOL didCancel = sender == self.cancelEditButton;
  MPDocument *document = [[self windowController] document];
  NSUndoManager *undoManager = [document undoManager];
  
  if(_isEditing) {
    BOOL didChangeItem = [undoManager canUndo];
    [undoManager endUndoGrouping];
    [undoManager setActionName:NSLocalizedString(@"EDIT_GROUP_OR_ENTRY", "")];
    [self.editButton setTitle:NSLocalizedString(@"EDIT_ITEM", "")];
    [self.cancelEditButton setHidden:YES];
    [_entryViewController endEditing];
    
    /*
     We need to be carefull to only undo the things we actually changed
     otherwise we undo older actions
     */
    if(didCancel && didChangeItem) {
      [undoManager undo];
    }
  }
  else {
    [undoManager beginUndoGrouping];
    [self.editButton setTitle:NSLocalizedString(@"SAVE_CHANGES", "")];
    [self.cancelEditButton setHidden:NO];
    [_entryViewController beginEditing];
  }
  _isEditing = !_isEditing;
}

#pragma mark -
#pragma mark Popup
- (IBAction)showImagePopup:(id)sender {
  
  NSAssert(_popover == nil, @"Popover hast to be niled out");
  _popover = [[NSPopover alloc] init];
  _popover.delegate = self;
  _popover.behavior = NSPopoverBehaviorTransient;
  if(!self.iconSelectionViewController) {
    self.iconSelectionViewController = [[MPIconSelectViewController alloc] init];
  }
  [self.iconSelectionViewController reset];
  self.iconSelectionViewController.popover = _popover;
  _popover.contentViewController = self.iconSelectionViewController;
  [_popover showRelativeToRect:NSZeroRect ofView:self.itemImageView preferredEdge:NSMinYEdge];
}

- (void)popoverDidClose:(NSNotification *)notification {
  MPIconSelectViewController *viewController = (MPIconSelectViewController *)_popover.contentViewController;
  if(!viewController.didCancel) {
    
    MPDocument *document = [[self windowController] document];
    BOOL useDefault = (viewController.selectedIcon == -1);
    switch (self.activeTab) {
      case MPGroupTab:
        document.selectedGroup.iconId = useDefault ? [KPKGroup defaultIcon] : viewController.selectedIcon;
        break;
        
      case MPEntryTab:
        document.selectedEntry.iconId = useDefault ? [KPKEntry defaultIcon]: viewController.selectedIcon;
        break;
        
      default:
        break;
    }
  }
  _popover = nil;
}

#pragma mark -
#pragma mark Bindings
- (void)_updateBindings:(id)item {
  if(!item) {
    [self.itemNameTextField unbind:NSValueBinding];
    [self.itemNameTextField setHidden:YES];
    [self.itemImageView unbind:NSValueBinding];
    [self.itemImageView setHidden:YES];
    [self.notesTextView unbind:NSValueBinding];
    [self.notesTextView setString:@""];
    [self.notesTextView setEditable:NO];
    
    return;
  }
  [self.itemImageView bind:NSValueBinding toObject:item withKeyPath:NSStringFromSelector(@selector(iconImage)) options:nil];
  [self.notesTextView setEditable:YES];
  [self.notesTextView bind:NSValueBinding toObject:item withKeyPath:NSStringFromSelector(@selector(notes)) options:nil];
  if([item respondsToSelector:@selector(title)]) {
    [self.itemNameTextField bind:NSValueBinding toObject:item withKeyPath:NSStringFromSelector(@selector(title)) options:nil];
  }
  else if( [item respondsToSelector:@selector(name)]) {
    [self.itemNameTextField bind:NSValueBinding toObject:item withKeyPath:NSStringFromSelector(@selector(name)) options:nil];
  }
  [self.itemImageView setHidden:NO];
  [self.itemNameTextField setHidden:NO];

  if([item respondsToSelector:@selector(notes)]) {
    
  }
}

#pragma mark -
#pragma mark Notificiations

- (void)_didChangeCurrentItem:(NSNotification *)notification {
  MPDocument *document = [notification object];
  if(!document.selectedItem) {
    /* show emty tab and hide edit button */
    self.activeTab = MPEmptyTab;
  }
  else {
    BOOL isGroup = document.selectedItem == document.selectedGroup;
    BOOL isEntry = document.selectedItem == document.selectedEntry;
    if(isGroup) {
      self.activeTab = MPGroupTab;
    }
    else if(isEntry) {
      self.activeTab = MPEntryTab;
    }
  }
  [self _updateBindings:document.selectedItem];
  
  /* disable the entry text fields whenever the entry selection changes */
  //[_entryViewController endEditing];
}
@end