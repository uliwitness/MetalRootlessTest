/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of renderer class which performs Metal setup and per frame rendering
*/

@import simd;
@import MetalKit;

#import "AAPLRenderer.h"
#import "AAPLImage.h"

// Header shared between C code here, which executes Metal API commands, and .metal files, which
//   uses these types as inputs to the shaders
#import "AAPLShaderTypes.h"

// Main class performing the rendering
@implementation AAPLRenderer
{
    // The device (aka GPU) we're using to render
    id<MTLDevice> _device;

    // Our render pipeline composed of our vertex and fragment shaders in the .metal shader file
    id<MTLRenderPipelineState> _pipelineState;

    // The command Queue from which we'll obtain command buffers
    id<MTLCommandQueue> _commandQueue;

    // The Metal texture object
    id<MTLTexture> _texture;

    // The Metal buffer in which we store our vertex data
    id<MTLBuffer> _vertices;

    // The number of vertices in our vertex buffer
    NSUInteger _numVertices;

    // The current size of our view so we can use this in our render pipeline
    vector_uint2 _viewportSize;
}

/// Initialize with the MetalKit view from which we'll obtain our Metal device
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        _device = mtkView.device;

        NSURL *imageFileLocation = [[NSBundle mainBundle] URLForResource:@"Image"
                                                           withExtension:@"tga"];

        AAPLImage * image = [[AAPLImage alloc] initWithTGAFileAtLocation:imageFileLocation];

        if(!image)
        {
            NSLog(@"Failed to create the image from %@", imageFileLocation.absoluteString);
            return nil;
        }

        MTLTextureDescriptor *textureDescriptor = [[MTLTextureDescriptor alloc] init];

        // Indicate that each pixel has a blue, green, red, and alpha channel, where each channel is
        // an 8-bit unsigned normalized value (i.e. 0 maps to 0.0 and 255 maps to 1.0)
        textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;

         // Set the pixel dimensions of the texture
        textureDescriptor.width = image.width;
        textureDescriptor.height = image.height;

        // Create the texture from the device by using the descriptor
        _texture = [_device newTextureWithDescriptor:textureDescriptor];

        // Calculate the number of bytes per row of our image.
        NSUInteger bytesPerRow = 4 * image.width;

        MTLRegion region = {
            { 0, 0, 0 },                   // MTLOrigin
            {image.width, image.height, 1} // MTLSize
        };

        // Copy the bytes from our data object into the texture
        [_texture replaceRegion:region
                    mipmapLevel:0
                      withBytes:image.data.bytes
                    bytesPerRow:bytesPerRow];

		float startX = 0, startY = 50, endX = image.width, endY = image.height;
		bool isMathematical = false;
		
		float realStartY = isMathematical ? endY : (image.height -startY);
		float realEndY = isMathematical ? startY : (image.height -endY);

		float	halfWidth = (endX - startX) / 2.0;
		float	halfHeight = (endY - startY) / 2.0;

        // Set up a simple MTLBuffer with our vertices which include texture coordinates
		static AAPLVertex quadVertices[6];
		
		quadVertices[0].position[0] = halfWidth;
		quadVertices[0].position[1] = -halfHeight;
		quadVertices[0].textureCoordinate[0] = endX / image.width;
		quadVertices[0].textureCoordinate[1] = realEndY / image.height;

		quadVertices[1].position[0] = -halfWidth;
		quadVertices[1].position[1] = -halfHeight;
		quadVertices[1].textureCoordinate[0] = startX / image.width;
		quadVertices[1].textureCoordinate[1] = realEndY / image.height;

		quadVertices[2].position[0] = -halfWidth;
		quadVertices[2].position[1] = halfHeight;
		quadVertices[2].textureCoordinate[0] = startX / image.width;
		quadVertices[2].textureCoordinate[1] = realStartY / image.height;

		quadVertices[3].position[0] = halfWidth;
		quadVertices[3].position[1] = -halfHeight;
		quadVertices[3].textureCoordinate[0] = endX / image.width;
		quadVertices[3].textureCoordinate[1] = realEndY / image.height;

		quadVertices[4].position[0] = -halfWidth;
		quadVertices[4].position[1] = halfHeight;
		quadVertices[4].textureCoordinate[0] = startX / image.width;
		quadVertices[4].textureCoordinate[1] = realStartY / image.height;

		quadVertices[5].position[0] = halfWidth;
		quadVertices[5].position[1] = halfHeight;
		quadVertices[5].textureCoordinate[0] = endX / image.width;
		quadVertices[5].textureCoordinate[1] = realStartY / image.height;

        // Create our vertex buffer, and initialize it with our quadVertices array
        _vertices = [_device newBufferWithBytes:quadVertices
                                         length:sizeof(quadVertices)
                                        options:MTLResourceStorageModeShared];

        // Calculate the number of vertices by dividing the byte length by the size of each vertex
        _numVertices = sizeof(quadVertices) / sizeof(AAPLVertex);

        /// Create our render pipeline

        // Load all the shader files with a .metal file extension in the project
        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

        // Load the vertex function from the library
        id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];

        // Load the fragment function from the library
        id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"samplingShader"];

        // Set up a descriptor for creating a pipeline state object
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Texturing Pipeline";
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;

        NSError *error = NULL;
        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                 error:&error];
        if (!_pipelineState)
        {
            // Pipeline State creation could fail if we haven't properly set up our pipeline descriptor.
            //  If the Metal API validation is enabled, we can find out more information about what
            //  went wrong.  (Metal API validation is enabled by default when a debug build is run
            //  from Xcode)
            NSLog(@"Failed to created pipeline state, error %@", error);
        }

        // Create the command queue
        _commandQueue = [_device newCommandQueue];
    }

    return self;
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Save the size of the drawable as we'll pass these
    //   values to our vertex shader when we draw
    _viewportSize.x = size.width;
    _viewportSize.y = size.height;
}

/// Called whenever the view needs to render a frame
- (void)drawInMTKView:(nonnull MTKView *)view
{

    // Create a new command buffer for each render pass to the current drawable
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";

    // Obtain a renderPassDescriptor generated from the view's drawable textures
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;

    if(renderPassDescriptor != nil)
    {
        // Create a render command encoder so we can render into something
        id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"MyRenderEncoder";

        // Set the region of the drawable to which we'll draw.
        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, _viewportSize.x, _viewportSize.y, -1.0, 1.0 }];

        [renderEncoder setRenderPipelineState:_pipelineState];

        [renderEncoder setVertexBuffer:_vertices
                                offset:0
                              atIndex:AAPLVertexInputIndexVertices];

        [renderEncoder setVertexBytes:&_viewportSize
                               length:sizeof(_viewportSize)
                              atIndex:AAPLVertexInputIndexViewportSize];

        // Set the texture object.  The AAPLTextureIndexBaseColor enum value corresponds
        ///  to the 'colorMap' argument in our 'samplingShader' function because its
        //   texture attribute qualifier also uses AAPLTextureIndexBaseColor for its index
        [renderEncoder setFragmentTexture:_texture
                                  atIndex:AAPLTextureIndexBaseColor];

        // Draw the vertices of our triangles
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:_numVertices];

        [renderEncoder endEncoding];

        // Schedule a present once the framebuffer is complete using the current drawable
        [commandBuffer presentDrawable:view.currentDrawable];
    }


    // Finalize rendering here & push the command buffer to the GPU
    [commandBuffer commit];
}

@end
