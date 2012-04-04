//
//  HeatMapView.m
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

#import "HeatMapView.h"
#import <CoreGraphics/CoreGraphics.h>

@implementation HeatMapView

- (id)initWithOverlay:(id <MKOverlay>)overlay
{
    if (self = [super initWithOverlay:overlay]) {
        
    }
    return self;
}

- (void)colorForValue:(double)value red:(CGFloat *)red green:(CGFloat *)green blue:(CGFloat *)blue alpha:(CGFloat *)alpha
{
    if (value > 1) value = 1;
    value = sqrt(value);
    
    if (value < PIVOT_X) {
        *alpha = value * PIVOT_Y / PIVOT_X;
    } else {
        *alpha = PIVOT_Y + ((MAX_ALPHA - PIVOT_Y) / (1 - PIVOT_X)) * (value - PIVOT_X);
    }
    
    //formula converts a number from 0 to 1.0 to an rgb color.
    //uses MATLAB/Octave colorbar code
    if(value <= 0) { 
        *red = *green = *blue = *alpha = 0;
    } else if(value < 0.125) {
        *red = *green = 0;
        *blue = 4 * (value + 0.125);
    } else if(value < 0.375) {
        *red = 0;
        *green = 4 * (value - 0.125);
        *blue = 1;
    } else if(value < 0.625) {
        *red = 4 * (value - 0.375);
        *green = 1;
        *blue = 1 - 4 * (value - 0.375);
    } else if(value < 0.875) {
        *red = 1;
        *green = 1 - 4 * (value - 0.625);
        *blue = 0;
    } else {
        *red = MAX(1 - 4 * (value - 0.875), 0.5);
        *green = *blue = 0;
    }
}

- (void)drawMapRect:(MKMapRect)mapRect
          zoomScale:(MKZoomScale)zoomScale
          inContext:(CGContextRef)context
{    
    CGRect usRect = [self rectForMapRect:mapRect]; //rect in user space coordinates (NOTE: not in screen points)
    
    int columns = ceil(CGRectGetWidth(usRect) * zoomScale);
    int rows = ceil(CGRectGetHeight(usRect) * zoomScale);
    int arrayLen = columns * rows;
    
    //allocate an array matching the screen point size of the rect
    float* pointValues = calloc(arrayLen, sizeof(float));
    
    if (pointValues) {
        //pad out the mapRect with the radius on all sides. 
        // we care about points that are not in (but close to) this rect
        CGRect paddedRect = [self rectForMapRect:mapRect];
        paddedRect.origin.x -= RADIUS / zoomScale;
        paddedRect.origin.y -= RADIUS / zoomScale;
        paddedRect.size.width += 2 * RADIUS / zoomScale;
        paddedRect.size.height += 2 * RADIUS / zoomScale;
        MKMapRect paddedMapRect = [self mapRectForRect:paddedRect];
        
        //Get the dictionary of values out of the model for this mapRect and zoomScale.
        HeatMap *hm = (HeatMap *)self.overlay;
        NSDictionary *heat = [hm mapPointsWithHeatInMapRect:paddedMapRect atScale:zoomScale];
        
        for (NSValue *key in heat) {
            //convert key to mapPoint
            MKMapPoint mapPoint;
            [key getValue:&mapPoint];
            double value = [[heat objectForKey:key] doubleValue];
            
            //figure out the correspoinding array index
            CGPoint usPoint = [self pointForMapPoint:mapPoint];
            
            CGPoint matrixCoord = CGPointMake((usPoint.x - usRect.origin.x) * zoomScale, 
                                              (usPoint.y - usRect.origin.y) * zoomScale);
            
            if (value > 0) { //don't bother with 0 or negative values
                //iterate through surrounding pixels and increase
                for(int i = 0; i < 2 * RADIUS; i++) {
                    for(int j = 0; j < 2 * RADIUS; j++) {
                        //find the array index
                        int column = matrixCoord.x - RADIUS + i;
                        int row = matrixCoord.y - RADIUS + j;
                        int index = columns * row + column;
                        
                        //make sure this is a valid array index
                        if(row >= 0 && column >= 0 && row < rows && column < columns) {
                            //compute the point's new value based on linear radial falloff
                            double distance = sqrt((i - RADIUS) * (i - RADIUS) + (j - RADIUS) * (j - RADIUS));
                            float newValue = value - value / RADIUS * distance;
                            if(newValue < 0) newValue = 0;
                            pointValues[index] += newValue;
                        }
                    }
                }
            }
        }
        
        for (int i = 0; i < arrayLen; i++) {
            if (pointValues[i] > 0) {
                int column = i % columns;
                int row = i / columns;
                CGFloat red, green, blue, alpha;
                
                //weird behaviour on the edges of the rect.
                //just steal the neighbour's value, makes it look much better
                //this is HACK and should be fixed
                if(row == 0) 
                    pointValues[i] = pointValues[i + columns];
                else if(column == 0) 
                    pointValues[i] = pointValues[i + 1];
                
                [self colorForValue:pointValues[i] red:&red green:&green blue:&blue alpha:&alpha];
                CGContextSetRGBFillColor(context, red, green, blue, alpha);
                
                //scale back up to userSpace
                CGRect matchingUsRect = CGRectMake(usRect.origin.x + column / zoomScale, 
                                                   usRect.origin.y + row / zoomScale, 
                                                   1/zoomScale, 
                                                   1/zoomScale);
                
                CGContextFillRect(context, matchingUsRect);
            }
        }
        
        free(pointValues);
    }
}

@end
