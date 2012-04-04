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

#define PADDING 100000
#define ZOOM_0_DIMENSION 256
#define MAPKIT_POINTS 536870912
#define ZOOM_LEVELS 20

//alterable constant to change look of heat map
#define POWER 4

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
        
        float *buckets = calloc(ZOOM_0_DIMENSION * ZOOM_0_DIMENSION, sizeof(float));
        
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
            int col = point.x / (MAPKIT_POINTS / ZOOM_0_DIMENSION);
            int row = point.y / (MAPKIT_POINTS / ZOOM_0_DIMENSION);
        
            int offset = ZOOM_0_DIMENSION * row + col;
        
            buckets[offset] += [value doubleValue];
        }
    
        for (int i = 0; i < ZOOM_0_DIMENSION * ZOOM_0_DIMENSION; i++) {
            if (buckets[i] > self.zoomedOutMax) 
                self.zoomedOutMax = buckets[i];
        }
        
        free(buckets);
        
        //make the new bounding region from the two corners
        //probably should do some cusioning
        double width = lowerRightPoint.x - upperLeftPoint.x + PADDING;
        double height = lowerRightPoint.y - upperLeftPoint.y + PADDING;
        
        self.boundingRect = MKMapRectMake(upperLeftPoint.x - PADDING / 2, upperLeftPoint.y - PADDING / 2, width, height);
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
    
    double zoomScale = log2(1/scale);
    double slope = (self.zoomedOutMax - self.max) / (ZOOM_LEVELS - 1);
    double x = pow(zoomScale, POWER) / pow(ZOOM_LEVELS, POWER - 1);
    double scaleFactor = (x - 1) * slope + self.max;
    
    if (scaleFactor < self.max) 
        scaleFactor = self.max;
    
    for(NSValue *key in self.pointsWithHeat) {
        MKMapPoint point;
        [key getValue:&point];
        
        if(MKMapRectContainsPoint(rect, point)) {
            //scale the value down by the max and add it to the return dictionary
            NSNumber *value = [self.pointsWithHeat objectForKey:key];
            double unscaled = [value doubleValue];
            double scaled = unscaled / scaleFactor;
            [toReturn setObject:[NSNumber numberWithDouble:scaled] forKey:key];
        }
    }
    
    return toReturn;
}

@end
