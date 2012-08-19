//
//  HeatMap.m
//  HeatMap
//
//  Created by Ryan Olson on 12-03-04.
//  Copyright (c) 2012 Ryan Olson. 
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is furnished
// to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "HeatMap.h"

static const CGFloat kSBMapRectPadding = 100000;
static const int kSBZoomZeroDimension = 256;
static const int kSBMapKitPoints = 536870912;
static const int kSBZoomLevels = 20;

// Alterable constant to change look of heat map
static const int kSBScalePower = 4;

// Alterable constant to trade off accuracy with performance
// Increase for big data sets which draw slowly
static const int kSBScreenPointsPerBucket = 10;

@interface HeatMap()

@property double max;
@property double zoomedOutMax;
@property (nonatomic) NSDictionary *pointsWithHeat;
@property CLLocationCoordinate2D center;
@property MKMapRect boundingRect;

@end

@implementation HeatMap

@synthesize max = _max;
@synthesize zoomedOutMax = _zoomedOutMax;
@synthesize pointsWithHeat = _pointsWithHeat;
@synthesize center = _center;
@synthesize boundingRect = _boundingRect;

- (id)initWithData:(NSDictionary *)heatMapData 
{
    if (self = [super init]) {
        [self setData:heatMapData];
    }
    return self;
}

- (void)setData:(NSDictionary *)newHeatMapData
{        
    if (newHeatMapData != _pointsWithHeat) {
    
        self.max = 0;
        
        MKMapPoint upperLeftPoint, lowerRightPoint;
        [[[newHeatMapData allKeys] lastObject] getValue:&upperLeftPoint];
        lowerRightPoint = upperLeftPoint;
        
        float *buckets = calloc(kSBZoomZeroDimension * kSBZoomZeroDimension, sizeof(float));
        
        //iterate through to find the max and the bounding region
        //set up the internal model with the data
        //TODO: make sure this dictionary has the correct typing
        for (NSValue *mapPointValue in newHeatMapData) {
            MKMapPoint point;
            [mapPointValue getValue:&point];
            
            if (point.x < upperLeftPoint.x) upperLeftPoint.x = point.x;
            if (point.y < upperLeftPoint.y) upperLeftPoint.y = point.y;
            if (point.x > lowerRightPoint.x) lowerRightPoint.x = point.x;
            if (point.y > lowerRightPoint.y) lowerRightPoint.y = point.y;
            
            NSNumber *value = [newHeatMapData objectForKey:mapPointValue];
            
            if ([value doubleValue] > self.max) {
                self.max = [value doubleValue];
            }
            
            //bucket the map point:
            int col = point.x / (kSBMapKitPoints / kSBZoomZeroDimension);
            int row = point.y / (kSBMapKitPoints / kSBZoomZeroDimension);
        
            int offset = kSBZoomZeroDimension * row + col;
        
            buckets[offset] += [value doubleValue];
        }
    
        for (int i = 0; i < kSBZoomZeroDimension * kSBZoomZeroDimension; i++) {
            if (buckets[i] > self.zoomedOutMax) 
                self.zoomedOutMax = buckets[i];
        }
        
        free(buckets);
        
        //make the new bounding region from the two corners
        //probably should do some cusioning
        double width = lowerRightPoint.x - upperLeftPoint.x + kSBMapRectPadding;
        double height = lowerRightPoint.y - upperLeftPoint.y + kSBMapRectPadding;
        
        self.boundingRect = MKMapRectMake(upperLeftPoint.x - kSBMapRectPadding / 2, upperLeftPoint.y - kSBMapRectPadding / 2, width, height);
        self.center = MKCoordinateForMapPoint(MKMapPointMake(upperLeftPoint.x + width / 2, upperLeftPoint.y + height / 2));
        
        _pointsWithHeat = newHeatMapData;
    }
}

- (CLLocationCoordinate2D)coordinate
{
    return self.center;
}

- (MKMapRect)boundingMapRect
{
    return self.boundingRect;
}

- (NSDictionary *)mapPointsWithHeatInMapRect:(MKMapRect)rect atScale:(MKZoomScale)scale
{
    NSMutableDictionary *toReturn = [[NSMutableDictionary alloc] init];
    int bucketDelta = kSBScreenPointsPerBucket / scale;
    
    double zoomScale = log2(1/scale);
    double slope = (self.zoomedOutMax - self.max) / (kSBZoomLevels - 1);
    double x = pow(zoomScale, kSBScalePower) / pow(kSBZoomLevels, kSBScalePower - 1);
    double scaleFactor = (x - 1) * slope + self.max;
    
    if (scaleFactor < self.max) 
        scaleFactor = self.max;
    
    for(NSValue *key in self.pointsWithHeat) {
        MKMapPoint point;
        [key getValue:&point];
        
        if(MKMapRectContainsPoint(rect, point)) {
            // Scale the value down by the max and add it to the return dictionary
            NSNumber *value = [self.pointsWithHeat objectForKey:key];
            double unscaled = [value doubleValue];
            double scaled = unscaled / scaleFactor;
            
            MKMapPoint bucketPoint;
            int originalX = point.x;
            int originalY = point.y;
            bucketPoint.x = originalX - originalX % bucketDelta + bucketDelta / 2;
            bucketPoint.y = originalY - originalY % bucketDelta + bucketDelta / 2;
            NSValue *bucketKey = [NSValue value:&bucketPoint withObjCType:@encode(MKMapPoint)];
            
            NSNumber *existingValue = [toReturn objectForKey:bucketKey];
            if (existingValue) {
                scaled += [existingValue doubleValue];
            }
            
            [toReturn setObject:[NSNumber numberWithDouble:scaled] forKey:bucketKey];
        }
    }
    
    return toReturn;
}

@end
