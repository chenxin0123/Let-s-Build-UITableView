//
//  PGTableView.m
//  Let's Build UITableView
//
//  Created by Matthew Elton on 19/01/2013.
//  www.obliquely.org.uk
//

#import "PGTableView.h"
#import "PGRowRecord.h"
#import "PGTableViewCell.h"

@interface PGTableView ()

@property (nonatomic, retain) NSMutableArray* rowRecords;///<保存所有行的高度和偏移信息
@property (nonatomic, retain) NSMutableSet* reusePool;///<重用池子
@property (nonatomic, retain) NSMutableIndexSet* visibleRows;

@end

@implementation PGTableView

@synthesize reusePool = _pgReusePool;
@synthesize visibleRows = _pgVisibleRows;
@synthesize rowRecords = _pgRowRecords;
@synthesize rowMargin = _pgRowMargin;

#pragma mark - init and dealloc

- (void) dealloc
{
    [_pgReusePool release];
    [_pgVisibleRows release];
    [_pgRowRecords release];
    [super dealloc];
}


- (id) initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder: aDecoder];
    if (self)
    {
        [self setup]; // called if created by a xib file
    }
    return self;
}


- (id) initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        [self setup];   // called if programmatically created
    }
    return self;
}


#pragma mark - public methods

- (PGTableViewCell*) dequeueReusableCellWithIdentifier: (NSString*) reuseIdentifier
{
    if ([self disablePool])
    {
        [self setReusePool: nil];   // empty pool
        return nil;                 // force creation of new view every time
    }
    
    PGTableViewCell* poolCell = nil;
    
    for (PGTableViewCell* tableViewCell in [self reusePool])
    {
        if ([[tableViewCell reuseIdentifier] isEqualToString: reuseIdentifier])
        {
            poolCell = tableViewCell;
            break;
        }
    }
    
    if (poolCell)
    {
        [poolCell retain];
        [[self reusePool] removeObject: poolCell];
        [poolCell autorelease];
    }

    // [self logPool: reuseIdentifier andCell: poolCell];
    
    return poolCell;
}



- (void) reloadData
{
    [self returnNonVisibleRowsToThePool: nil];
    [self generateHeightAndOffsetData];
    [self layoutTableRows];
}



// bonus content - change the height of just one row w/o asking every row for new height
- (void) row: (NSInteger) row changedHeight: (CGFloat) height
{
    PGRowRecord* rowRecord = (PGRowRecord*)[[self rowRecords] objectAtIndex: row];
    CGFloat adjust = height - [rowRecord height];
    [rowRecord setHeight: height];
    
    if ([rowRecord cachedCell])
    {
        [[rowRecord cachedCell] removeFromSuperview];
        [[self reusePool] addObject: [rowRecord cachedCell]];
        [rowRecord setCachedCell: nil];
    }
    
    for (NSInteger index = row + 1; index < [[self rowRecords] count]; index++)
    {
        rowRecord = (PGRowRecord*)[[self rowRecords] objectAtIndex: index];
        [rowRecord setStartPositionY: [rowRecord startPositionY] + adjust];
        
        if ([rowRecord cachedCell])
        {
            [[rowRecord cachedCell] removeFromSuperview];
            [[self reusePool] addObject: [rowRecord cachedCell]];
            [rowRecord setCachedCell: nil];
        }
    }
    
    [self setContentSize: CGSizeMake([self contentSize].width, [self contentSize].height + adjust)];
    
    [self layoutTableRows];
}

- (NSIndexSet*) indexSetOfVisibleRows
{
    return [[[self visibleRows] copy] autorelease];
}


#pragma mark - scrollView overrides

- (void) setContentOffset:(CGPoint)contentOffset //  note: this method called frequently - needs to be fast
{
    [super setContentOffset: contentOffset];
    [self layoutTableRows];
}


#pragma mark - layout the table rows

///获取所有可见的行 获取cell
- (void) layoutTableRows
{
    CGFloat currentStartY = [self contentOffset].y;
    CGFloat currentEndY = currentStartY + [self frame].size.height;
    
    NSInteger rowToDisplay = [self findRowForOffsetY: currentStartY inRange: NSMakeRange(0, [[self rowRecords] count])];
   
    NSMutableIndexSet* newVisibleRows = [[NSMutableIndexSet alloc] init];
    
    CGFloat yOrigin;
    CGFloat rowHeight;
    do
    {
        [newVisibleRows addIndex: rowToDisplay];
        
        yOrigin = [self startPositionYForRow: rowToDisplay];
        rowHeight = [self heightForRow: rowToDisplay];
        
        //获取该row对应的cell
        PGTableViewCell* cell = [self cachedCellForRow: rowToDisplay];
        
        if (!cell)
        {
            cell = [[self dataSource] pgTableView: self cellForRow: rowToDisplay];
            [self setCachedCell: cell forRow: rowToDisplay];
      
            [cell setFrame: CGRectMake(0.0, yOrigin, [self bounds].size.width, rowHeight - _pgRowMargin)];
            [self addSubview: cell];
        }
        
        rowToDisplay++;
    }
    while (yOrigin + rowHeight < currentEndY && rowToDisplay < [[self rowRecords] count]);

    
    NSLog(@"laying out %d row", [newVisibleRows count]);
    
    [self returnNonVisibleRowsToThePool: newVisibleRows];

    [newVisibleRows release];
}


///设置新的可见行 将旧的移除并将旧的cell放入reusePool
- (void) returnNonVisibleRowsToThePool: (NSMutableIndexSet*) currentVisibleRows
{
    [[self visibleRows] removeIndexes: currentVisibleRows];
    [[self visibleRows] enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop)
     {
         PGTableViewCell* tableViewCell = [self cachedCellForRow: row];
         if (tableViewCell)
         {
             [[self reusePool] addObject: tableViewCell];
             [tableViewCell removeFromSuperview];
             [self setCachedCell: nil forRow: row];
         }
     }];
    [self setVisibleRows: currentVisibleRows];
}

///计算并保存每行的高度和offset
- (void) generateHeightAndOffsetData
{
    CGFloat currentOffsetY = 0.0;
    
    BOOL checkHeightForEachRow = [[self delegate] respondsToSelector: @selector(pgTableView:heightForRow:)];
    
    //询问行高
    NSMutableArray* newRowRecords = [NSMutableArray array];
    
    //行数
    NSInteger numberOfRows = [[self dataSource] numberOfRowsInPgTableView: self];

    //保存所有行的信息
    for (NSInteger row = 0; row < numberOfRows; row++)
    {
        PGRowRecord* rowRecord = [[PGRowRecord alloc] init];
        
        CGFloat rowHeight = checkHeightForEachRow ? [[self delegate] pgTableView: self heightForRow: row] : [self rowHeight];
        
        [rowRecord setHeight: rowHeight + _pgRowMargin];
        [rowRecord setStartPositionY: currentOffsetY + _pgRowMargin];
        
        [newRowRecords insertObject: rowRecord atIndex: row];
        [rowRecord release];
        
        currentOffsetY = currentOffsetY + rowHeight + _pgRowMargin;
    }
    
    [self setRowRecords: newRowRecords];
    
    [self setContentSize: CGSizeMake([self bounds].size.width,  currentOffsetY)];
}

///返回Y坐标对应的PGRowRecord的index
- (NSInteger) findRowForOffsetY: (CGFloat) yPosition inRange: (NSRange) range
{
    if ([[self rowRecords] count] == 0) return 0;
    
    PGRowRecord* rowRecord = [[PGRowRecord alloc] init];
    [rowRecord setStartPositionY: yPosition];
    
    NSInteger returnValue = [[self rowRecords] indexOfObject: rowRecord
                                               inSortedRange: NSMakeRange(0, [[self rowRecords] count])
                                                     options: NSBinarySearchingInsertionIndex
                                             usingComparator: ^NSComparisonResult(PGRowRecord* rowRecord1, PGRowRecord* rowRecord2){
                                                 if ([rowRecord1 startPositionY] < [rowRecord2 startPositionY]) return NSOrderedAscending;
                                                 return NSOrderedDescending;
                                             }];
    [rowRecord release];
    if (returnValue == 0) return 0;
    return returnValue-1;
}



#pragma mark - convenience methods for accessing row records

- (CGFloat) startPositionYForRow: (NSInteger) row
{
    return [(PGRowRecord*)[[self rowRecords] objectAtIndex: row] startPositionY];
}

- (CGFloat) heightForRow: (NSInteger) row
{
    return [(PGRowRecord*)[[self rowRecords] objectAtIndex: row] height];
}


- (PGTableViewCell*) cachedCellForRow: (NSInteger) row
{
    return [(PGRowRecord*)[[self rowRecords] objectAtIndex: row] cachedCell];
}

- (void) setCachedCell: (PGTableViewCell*) cell forRow: (NSInteger) row
{
    [(PGRowRecord*)[[self rowRecords] objectAtIndex: row] setCachedCell: cell];
}


#pragma mark - service methods and lazy instantiation

- (void) setup;
{
    [self setRowHeight: 40.0];  // default value for row height
    [self setRowMargin: 2.0];
}

///NSMutableSet
- (NSMutableSet*) reusePool
{
    if (!_pgReusePool)
    {
        _pgReusePool = [[NSMutableSet alloc] init];
    }
    
    return _pgReusePool;
}

///NSMutableIndexSet
- (NSMutableIndexSet*) visibleRows
{
    if (!_pgVisibleRows)
    {
        _pgVisibleRows = [[NSMutableIndexSet alloc] init];
    }
    
    return _pgVisibleRows;
}

#pragma mark - logging and debugging

- (void) logPool: (NSString*) reuseIdentifier andCell: (PGTableViewCell*) cell

{
    NSArray* poolIds= [[[self reusePool] allObjects] valueForKey: @"reuseIdentifier"];
    NSString* poolDescription = [poolIds componentsJoinedByString: @", "];
    
    NSString* recycle = @"Recyling a";
    if (!cell)
    {
        recycle = @"Making a new";
    }
    
    NSLog(@"%@ %@ cell. Pool contains %d items (%@)", recycle, reuseIdentifier, [[self reusePool] count], poolDescription);
}



- (NSInteger) OLDfindRowForOffsetY: (CGFloat) yPosition inRange: (NSRange) range
{
    if (range.length < 2)
    {
        return (range.location<1) ? range.location : range.location - 1;
    }
    
    NSInteger halfwayMark = range.length / 2;
    
    if (yPosition > [self startPositionYForRow: range.location + halfwayMark])
    {
        return [self findRowForOffsetY: yPosition inRange: NSMakeRange(range.location + (halfwayMark + 1), range.length - (halfwayMark +1))];
    }
    else
    {
        return [self findRowForOffsetY: yPosition inRange: NSMakeRange(range.location, range.length - halfwayMark)];
    }
}


- (NSInteger) inefficientFindRowForOffsetY: (CGFloat) yPosition inRange: (NSRange) range
{
    if (range.length == 0) return 0;
    
    NSInteger row = range.location;
    
    while (row < range.length)
    {
        if (yPosition < [self startPositionYForRow: row]) return (row<1) ? row : row - 1;
        row++;
    }
    row--;
    return row;
}



@end
