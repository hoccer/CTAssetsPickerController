/*
 CTAssetsGroupViewController.m
 
 The MIT License (MIT)
 
 Copyright (c) 2013 Clement CN Tsang
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.

 */

#import "CTAssetsPickerConstants.h"
#import "CTAssetsPickerController.h"
#import "CTAssetsGroupViewController.h"
#import "CTAssetsGroupViewCell.h"
#import "CTAssetsViewController.h"

#import "HXOUI.h"
#import "JGMediaQueryViewController.h"

#import <MediaPlayer/MediaPlayer.h>

NSString * const kSongs     = @"Songs";
NSString * const kArtists   = @"Artists";
NSString * const kAlbums    = @"Albums";
NSString * const kPlaylists = @"Playlists";

@interface CTAssetsPickerController ()

@property (nonatomic, strong) ALAssetsLibrary *assetsLibrary;

- (void)dismiss:(id)sender;
- (void)finishPickingAssets:(id)sender;

- (NSString *)toolbarTitle;
- (UIView *)notAllowedView;
- (UIView *)noAssetsView;

@end

@interface CTAssetsGroupViewController()

@property (nonatomic, weak) CTAssetsPickerController *picker;
@property (nonatomic, strong) NSMutableArray *groups;
@property (nonatomic, strong) ALAssetsGroup *defaultGroup;

@property (nonatomic, strong) UISegmentedControl * sourceToggle;
@property (nonatomic, readonly) NSArray * toplevelLibraryGroups;
@property (nonatomic, readonly) BOOL browsingAlbums;

@end

@implementation CTAssetsGroupViewController

- (id)init
{
    if (self = [super initWithStyle:UITableViewStylePlain])
    {
        self.preferredContentSize = kPopoverContentSize;
        [self addNotificationObserver];
    }
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self setupViews];
    [self setupButtons];
    [self setupToolbar];
    [self setupGroup];
}

- (void)dealloc
{
    [self removeNotificationObserver];
}


#pragma mark - Accessors

- (CTAssetsPickerController *)picker
{
    return (CTAssetsPickerController *)self.navigationController.parentViewController;
}


#pragma mark - Rotation

- (BOOL)shouldAutorotate
{
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAllButUpsideDown;
}


#pragma mark - Setup

- (void)setupViews
{
}

- (void)setupButtons
{
    if (self.picker.showsCancelButton)
    {
        self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Cancel", nil)
                                         style:UIBarButtonItemStylePlain
                                        target:self.picker
                                        action:@selector(dismiss:)];
    }
    
    self.navigationItem.rightBarButtonItem =
    [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Done", nil)
                                     style:UIBarButtonItemStyleDone
                                    target:self.picker
                                    action:@selector(finishPickingAssets:)];
    
    self.navigationItem.rightBarButtonItem.enabled = (self.picker.selectedAssets.count > 0);

    self.sourceToggle = [[UISegmentedControl alloc] initWithItems: @[NSLocalizedString(@"attachment_browse_album", nil), NSLocalizedString(@"attachment_browse_library", nil)]];
    [self.sourceToggle addTarget:self action: @selector(didToggleSource:) forControlEvents: UIControlEventValueChanged];
    self.navigationItem.titleView = self.sourceToggle;
    self.sourceToggle.selectedSegmentIndex = 0;
    [self didToggleSource: self.sourceToggle];
}

- (void) didToggleSource: (UISegmentedControl*) control {
    self.tableView.rowHeight = (self.browsingAlbums  ? kThumbnailLength : 32) + kHXOCellPadding;
    self.tableView.separatorStyle = self.browsingAlbums ? UITableViewCellSeparatorStyleNone : UITableViewCellSeparatorStyleSingleLine;

    [self reloadData];
}

- (BOOL) browsingAlbums {
    return self.sourceToggle.selectedSegmentIndex == 0;
}

- (void)setupToolbar
{
    self.toolbarItems = self.picker.toolbarItems;
}

- (void)setupGroup
{
    if (!self.groups)
        self.groups = [[NSMutableArray alloc] init];
    else
        [self.groups removeAllObjects];
    
    ALAssetsFilter *assetsFilter = self.picker.assetsFilter;
    
    ALAssetsLibraryGroupsEnumerationResultsBlock resultsBlock = ^(ALAssetsGroup *group, BOOL *stop)
    {
        if (group)
        {
            [group setAssetsFilter:assetsFilter];
            
            BOOL shouldShowGroup;
            
            if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:shouldShowAssetsGroup:)])
                shouldShowGroup = [self.picker.delegate assetsPickerController:self.picker shouldShowAssetsGroup:group];
            else
                shouldShowGroup = YES;
            
            if (shouldShowGroup)
            {
                [self.groups addObject:group];
                
                if ([self.picker.delegate respondsToSelector:@selector(assetsPickerController:isDefaultAssetsGroup:)])
                {
                    if ([self.picker.delegate assetsPickerController:self.picker isDefaultAssetsGroup:group])
                        self.defaultGroup = group;
                }
            }
        }
        else
        {
            [self reloadData];
        }
    };
    
    ALAssetsLibraryAccessFailureBlock failureBlock = ^(NSError *error)
    {
        [self showNotAllowed];
    };
    
    // Enumerate Camera roll first
    [self.picker.assetsLibrary enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos
                                             usingBlock:resultsBlock
                                           failureBlock:failureBlock];
    
    // Then all other groups
    NSUInteger type =
    ALAssetsGroupLibrary | ALAssetsGroupAlbum | ALAssetsGroupEvent |
    ALAssetsGroupFaces | ALAssetsGroupPhotoStream;
    
    [self.picker.assetsLibrary enumerateGroupsWithTypes:type
                                             usingBlock:resultsBlock
                                           failureBlock:failureBlock];
}


#pragma mark - Notifications

- (void)addNotificationObserver
{
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    
    [center addObserver:self
               selector:@selector(assetsLibraryChanged:)
                   name:ALAssetsLibraryChangedNotification
                 object:nil];
    
    [center addObserver:self
               selector:@selector(selectedAssetsChanged:)
                   name:CTAssetsPickerSelectedAssetsChangedNotification
                 object:nil];
}

- (void)removeNotificationObserver
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ALAssetsLibraryChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:CTAssetsPickerSelectedAssetsChangedNotification object:nil];
}


#pragma mark - Assets Library Changed

- (void)assetsLibraryChanged:(NSNotification *)notification
{
    // Reload all groups
    if (notification.userInfo == nil)
        [self performSelectorOnMainThread:@selector(setupGroup) withObject:nil waitUntilDone:NO];
    
    // Reload effected assets groups
    if (notification.userInfo.count > 0)
    {
        [self reloadAssetsGroupForUserInfo:notification.userInfo
                                       key:ALAssetLibraryUpdatedAssetGroupsKey
                                    action:@selector(updateAssetsGroupForURL:)];
        
        [self reloadAssetsGroupForUserInfo:notification.userInfo
                                       key:ALAssetLibraryInsertedAssetGroupsKey
                                    action:@selector(insertAssetsGroupForURL:)];
        
        [self reloadAssetsGroupForUserInfo:notification.userInfo
                                       key:ALAssetLibraryDeletedAssetGroupsKey
                                    action:@selector(deleteAssetsGroupForURL:)];
    }
}


#pragma mark - Reload Assets Group

- (void)reloadAssetsGroupForUserInfo:(NSDictionary *)userInfo key:(NSString *)key action:(SEL)selector
{
    NSSet *URLs = [userInfo objectForKey:key];
    
    for (NSURL *URL in URLs.allObjects)
        [self performSelectorOnMainThread:selector withObject:URL waitUntilDone:NO];
}

- (NSUInteger)indexOfAssetsGroupWithURL:(NSURL *)URL
{
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(ALAssetsGroup *group, NSDictionary *bindings){
        return [[group valueForProperty:ALAssetsGroupPropertyURL] isEqual:URL];
    }];
    
    return [self.groups indexOfObject:[self.groups filteredArrayUsingPredicate:predicate].firstObject];
}

- (void)updateAssetsGroupForURL:(NSURL *)URL
{
    ALAssetsLibraryGroupResultBlock resultBlock = ^(ALAssetsGroup *group){
        
        NSUInteger index = [self.groups indexOfObject:group];
        
        if (index != NSNotFound)
        {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            
            [self.groups replaceObjectAtIndex:index withObject:group];
            [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    };
    
    [self.picker.assetsLibrary groupForURL:URL resultBlock:resultBlock failureBlock:nil];
}

- (void)insertAssetsGroupForURL:(NSURL *)URL
{
    ALAssetsLibraryGroupResultBlock resultBlock = ^(ALAssetsGroup *group){
        
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:self.groups.count inSection:0];
        
        [self.tableView beginUpdates];
        
        [self.groups addObject:group];
        [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        
        [self.tableView endUpdates];
    };
    
    [self.picker.assetsLibrary groupForURL:URL resultBlock:resultBlock failureBlock:nil];
}

- (void)deleteAssetsGroupForURL:(NSURL *)URL
{
    NSUInteger index = [self indexOfAssetsGroupWithURL:URL];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
    
    [self.tableView beginUpdates];
    
    [self.groups removeObjectAtIndex:index];
    [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    
    [self.tableView endUpdates];
}


#pragma mark - Selected Assets Changed

- (void)selectedAssetsChanged:(NSNotification *)notification
{
    NSArray *selectedAssets = (NSArray *)notification.object;
    
    [[self.toolbarItems objectAtIndex:1] setTitle:[self.picker toolbarTitle]];
    
    [self.navigationController setToolbarHidden:(selectedAssets.count == 0) animated:YES];
}


#pragma mark - Reload Data

- (void)reloadData
{
    if (self.groups.count > 0)
    {
        [self hideAuxiliaryView];
        [self.tableView reloadData];
        [self pushDefaultAssetsGroup:self.defaultGroup];
    }
    else
    {
        [self showNoAssets];
    }
}
            
            
#pragma mark - Default Assets Group

- (void)pushDefaultAssetsGroup:(ALAssetsGroup *)group
{
    if (group)
    {
        CTAssetsViewController *vc = [[CTAssetsViewController alloc] init];
        vc.assetsGroup = group;
        
        self.navigationController.viewControllers = @[self, vc];
    }
}
    


#pragma mark - Not allowed / No assets

- (void)showNotAllowed
{
    self.title = nil;
    self.tableView.backgroundView = [self.picker notAllowedView];
    [self setAccessibilityFocus];
}

- (void)showNoAssets
{
    self.tableView.backgroundView = [self.picker noAssetsView];
    [self setAccessibilityFocus];
}

- (void)hideAuxiliaryView
{
    self.tableView.backgroundView = nil;
}

- (void)setAccessibilityFocus
{
    self.tableView.accessibilityLabel = self.tableView.backgroundView.accessibilityLabel;
    self.tableView.isAccessibilityElement = YES;
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.tableView);
}



#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.browsingAlbums ? self.groups.count : self.toplevelLibraryGroups.count;
}

- (NSArray*) toplevelLibraryGroups {
    return @[kSongs, kArtists, kAlbums, kPlaylists];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    
    CTAssetsGroupViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    if (cell == nil)
        cell = [[CTAssetsGroupViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];

    if (self.browsingAlbums) {
        [cell bind:[self.groups objectAtIndex:indexPath.row] showNumberOfAssets:self.picker.showsNumberOfAssets];
    } else {
        cell.tag = indexPath.row; // TODO: change this to get better decoupling... good enough for now though.
        cell.textLabel.text = NSLocalizedString(self.toplevelLibraryGroups[indexPath.row], nil);
        cell.imageView.image = nil;
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    return cell;
}


#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UIViewController * vc = nil;
    if (self.browsingAlbums) {
        CTAssetsViewController * assetView = [[CTAssetsViewController alloc] init];
        assetView.assetsGroup = [self.groups objectAtIndex:indexPath.row];
        vc = assetView;
    } else {
        UITableViewCell * cell = [self.tableView cellForRowAtIndexPath: indexPath];
        NSString * groupName = self.toplevelLibraryGroups[cell.tag];

        if ([kSongs isEqualToString: groupName]) {
            JGMediaQueryViewController *songsViewController = [[JGMediaQueryViewController alloc] initWithNibName:@"JGMediaQueryViewController" bundle:nil];
            songsViewController.queryType = JGMediaQueryTypeSongs;
            songsViewController.mediaQuery = [MPMediaQuery songsQuery];
            songsViewController.title = NSLocalizedString(@"Songs", @"Songs");
            songsViewController.delegate = self;
            songsViewController.showsCancelButton = YES;
            songsViewController.allowsSelectionOfNonPlayableItem = NO;
            vc = songsViewController;
        } else if ([kArtists isEqualToString: groupName]) {
            JGMediaQueryViewController *artistsViewController = [[JGMediaQueryViewController alloc] initWithNibName:@"JGMediaQueryViewController" bundle:nil];
            artistsViewController.queryType = JGMediaQueryTypeArtists;
            artistsViewController.mediaQuery = [MPMediaQuery artistsQuery];
            artistsViewController.title = NSLocalizedString(@"Artists", @"Artists");
            artistsViewController.delegate = self;
            artistsViewController.showsCancelButton = YES;
            artistsViewController.allowsSelectionOfNonPlayableItem = NO;
            vc = artistsViewController;
        } else if ([kAlbums isEqualToString: groupName]) {
            JGMediaQueryViewController *albumsViewController = [[JGMediaQueryViewController alloc] initWithNibName:@"JGMediaQueryViewController" bundle:nil];
            albumsViewController.queryType = JGMediaQueryTypeAlbums;
            albumsViewController.mediaQuery = [MPMediaQuery albumsQuery];
            albumsViewController.title = NSLocalizedString(@"Albums", @"Albums");
            albumsViewController.delegate = self;
            albumsViewController.showsCancelButton = YES;
            albumsViewController.allowsSelectionOfNonPlayableItem = NO;
            vc = albumsViewController;
        } else if ([kPlaylists isEqualToString: groupName]) {
            JGMediaQueryViewController *playlistsViewController = [[JGMediaQueryViewController alloc] initWithNibName:@"JGMediaQueryViewController" bundle:nil];
            playlistsViewController.queryType = JGMediaQueryTypePlaylists;
            playlistsViewController.mediaQuery = [MPMediaQuery playlistsQuery];
            playlistsViewController.title = NSLocalizedString(@"Playlists", @"Playlists");
            playlistsViewController.delegate = self;
            playlistsViewController.showsCancelButton = YES;
            playlistsViewController.allowsSelectionOfNonPlayableItem = NO;
            vc = playlistsViewController;
        } else {
            NSLog(@"Unhandled subview %@", groupName);
        }
    }
    [self.navigationController pushViewController: vc animated: YES];
}

#pragma mark - JGMediaPickerDelegate 

- (void)jgMediaQueryViewController:(JGMediaQueryViewController *)mediaQueryViewController didPickMediaItems:(MPMediaItemCollection *)mediaItemCollection selectedItem:(MPMediaItem *)selectedItem {

    //NSLog(@"selected %@", selectedItem);
    [self.picker selectMediaItem: selectedItem];
}

- (void)jgMediaQueryViewController:(JGMediaQueryViewController *)mediaPicker deselectItem: (MPMediaItem*) item {
    [self.picker deselectMediaItem: item];
}


- (void)jgMediaQueryViewControllerDidCancel:(JGMediaQueryViewController *)mediaPicker {
    [self.picker dismiss: self];
}

- (BOOL)jgMediaQueryViewController:(JGMediaQueryViewController *)mediaPicker isItemSelected: (MPMediaItem*) item {
    return [self.picker.selectedAssets indexOfObject: item] != NSNotFound;
}

- (NSArray*) selectedItems {
    return self.picker.selectedAssets;
}


@end