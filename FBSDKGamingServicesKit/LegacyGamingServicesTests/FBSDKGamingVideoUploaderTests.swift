// Copyright (c) 2014-present, Facebook, Inc. All rights reserved.
//
// You are hereby granted a non-exclusive, worldwide, royalty-free license to use,
// copy, modify, and distribute this software in source code or binary form for use
// in connection with the web services and APIs provided by Facebook.
//
// As with any software that integrates with the Facebook platform, your use of
// this software is subject to the Facebook Developer Principles and Policies
// [http://developers.facebook.com/policy/]. This copyright notice shall be
// included in all copies or substantial portions of the software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
// FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import LegacyGamingServices
import TestTools
import XCTest

class GamingVideoUploaderTests: XCTestCase {

  var videoURL = URL(string: "file://video.mp4")! // swiftlint:disable:this force_unwrapping
  lazy var configuration = createConfiguration(url: videoURL)
  let fileHandle = TestFileHandler()
  let fileHandleFactory = TestFileHandleFactory()
  let videoUploader = TestVideoUploader()
  let videoUploaderFactory = TestVideoUploaderFactory()
  lazy var uploader = GamingVideoUploader(
    fileHandleFactory: fileHandleFactory,
    videoUploaderFactory: videoUploaderFactory
  )

  override func setUp() {
    super.setUp()

    fileHandle.stubbedSeekToEndOfFile = UInt64.random(in: 1 ... 1000)
    fileHandleFactory.stubbedFileHandle = fileHandle
    videoUploaderFactory.stubbedVideoUploader = videoUploader

    AccessToken.current = SampleAccessTokens.validToken
  }

  func testDefaults() {
    XCTAssertTrue(
      GamingVideoUploader.shared.fileHandleFactory is FileHandleFactory,
      "Should have the expected file handle factory by default"
    )
    XCTAssertTrue(
      GamingVideoUploader.shared.videoUploaderFactory is VideoUploaderFactory,
      "Should have the expected video uploader factory by default"
    )
  }

  func testCreatingWithDependencies() {
    XCTAssertEqual(
      ObjectIdentifier(uploader.fileHandleFactory),
      ObjectIdentifier(fileHandleFactory),
      "Should be able to create an uploader with a custom file handle factory"
    )
    XCTAssertEqual(
      ObjectIdentifier(uploader.videoUploaderFactory),
      ObjectIdentifier(videoUploaderFactory),
      "Should be able to create an uploader with a custom video uploader factory"
    )
  }

  func testFailureWhenNoValidAccessTokenPresent() {
    AccessToken.current = nil

    var wasCompletionCalled = false
    GamingVideoUploader.uploadVideo(with: configuration) { _, _, error in
      XCTAssertEqual(
        (error as NSError?)?.code,
        CoreError.errorAccessTokenRequired.rawValue,
        "Expected error requiring a valid access token"
      )
      wasCompletionCalled = true
    }

    XCTAssertTrue(wasCompletionCalled)
  }

  func testBadVideoURLFails() {
    videoURL = URL(string: "file://not-a-video.mp4")! // swiftlint:disable:this force_unwrapping

    var wasCompletionCalled = false
    GamingVideoUploader.uploadVideo(with: configuration) { _, _, error in
      XCTAssertEqual(
        (error as NSError?)?.code,
        CoreError.errorInvalidArgument.rawValue,
        "Expected error requiring a non nil video url"
      )
      wasCompletionCalled = true
    }
    XCTAssertTrue(wasCompletionCalled)
  }

  func testCreatesFileHandle() {
    uploader.uploadVideo(with: configuration) { _, _, _ in
      XCTFail("Should not invoke the completion handler")
    }

    XCTAssertEqual(
      fileHandleFactory.capturedURL,
      videoURL,
      "Should create a file handle with the url from the configuration"
    )
  }

  func testUploadingEmptyFile() {
    fileHandle.stubbedSeekToEndOfFile = 0
    fileHandleFactory.stubbedFileHandle = fileHandle

    var wasCompletionCalled = false
    uploader.uploadVideo(with: configuration) { _, _, error in
      XCTAssertEqual(
        (error as NSError?)?.code,
        CoreError.errorInvalidArgument.rawValue,
        "Expected error requiring a non empty video file"
      )
      wasCompletionCalled = true
    }
    XCTAssertTrue(wasCompletionCalled)
  }

  func testCreatesAndStartsUploader() {
    uploader.uploadVideo(with: configuration) { _, _, _ in
      XCTFail("Should not invoke the completion handler")
    }
    XCTAssertTrue(
      self.videoUploaderFactory.capturedDelegate is GamingVideoUploader,
      "Should create an uploader with the expected delegate type"
    )
    XCTAssertEqual(
      self.videoUploaderFactory.capturedVideoName,
      self.videoURL.lastPathComponent,
      "Should use the video url to derive the video name"
    )
    XCTAssertTrue(
      self.videoUploaderFactory.capturedParameters.isEmpty,
      "Should not create an uploader with parameters"
    )
    XCTAssertEqual(
      self.videoUploaderFactory.capturedVideoSize,
      UInt(self.fileHandle.seekToEndOfFile()),
      "Should create an uploader with the size of the video being uploaded"
    )
    XCTAssertTrue(
      self.videoUploader.wasStartCalled,
      "Should start the upload"
    )
  }

  // MARK: Delegate methods

  func testUploadErrorsHandled() throws {
    var wasCompletionCalled = false
    uploader.uploadVideo(with: configuration) { _, _, error in
      XCTAssertTrue(error is SampleError)

      wasCompletionCalled = true
    }

    let delegate = try XCTUnwrap(videoUploaderFactory.capturedDelegate as? GamingVideoUploader)

    delegate.videoUploader(nil, didFailWithError: SampleError())

    XCTAssertTrue(wasCompletionCalled)
  }

  func testVideoUploaderErrorOnUnsuccessful() throws {
    var wasCompletionCalled = false
    uploader.uploadVideo(with: configuration) { _, _, error in
      XCTAssertEqual(
        (error as NSError?)?.code,
        CoreError.errorUnknown.rawValue,
        "Should callback with an unknown error when the result indicates failure"
      )
      wasCompletionCalled = true
    }

    let delegate = try XCTUnwrap(videoUploaderFactory.capturedDelegate as? GamingVideoUploader)

    delegate.videoUploader(nil, didCompleteWithResults: ["success": false])

    XCTAssertTrue(wasCompletionCalled)
  }

  func testVideoUploaderSucceeds() throws {
    var wasCompletionCalled = false
    uploader.uploadVideo(with: configuration) { success, _, error in
      XCTAssertNil(error, "Should not receive an error when the uploader succeeds")
      XCTAssertTrue(success, "Should indicate success in the completion")
      wasCompletionCalled = true
    }

    let delegate = try XCTUnwrap(videoUploaderFactory.capturedDelegate as? GamingVideoUploader)

    delegate.videoUploader(nil, didCompleteWithResults: ["success": "1"])

    XCTAssertTrue(wasCompletionCalled)
  }

  func testVideoUploaderProgress() throws {
    var expectedBytesSent: Int64 = 0
    var expectedTotalSent: Int64 = 0
    var expectedTotalExpected: Int64 = 999
    var completionCallCount = 0

    let verifyProgress: GamingServiceProgressHandler = { bytesSent, totalSent, totalExpected in
      XCTAssertEqual(bytesSent, expectedBytesSent)
      XCTAssertEqual(totalSent, expectedTotalSent)
      XCTAssertEqual(totalExpected, expectedTotalExpected)
      completionCallCount += 1
    }
    fileHandle.stubbedSeekToEndOfFile = 999
    fileHandle.stubbedReadData = Data(Array(repeating: 1, count: 500))

    uploader.uploadVideo(
      with: configuration,
      completionHandler: { _, _, _ in },
      andProgressHandler: verifyProgress
    )
    let delegate = try XCTUnwrap(videoUploaderFactory.capturedDelegate as? GamingVideoUploader)

    // Send first chunk of data
    delegate.videoChunkData(for: nil, startOffset: 0, endOffset: 500)

    // Set expectations
    expectedBytesSent = 500
    expectedTotalSent = 500
    expectedTotalExpected = 999

    fileHandle.stubbedReadData = Data(Array(repeating: 1, count: 499))

    // Send second chunk of data
    delegate.videoChunkData(for: nil, startOffset: 500, endOffset: 999)

    // Set expectations
    expectedBytesSent = 499
    expectedTotalSent = 999
    expectedTotalExpected = 999

    // Completing calls the progress handler with the final total bytes
    delegate.videoUploader(nil, didCompleteWithResults: ["success": true])

    XCTAssertEqual(completionCallCount, 3)
  }

  // MARK: - Helpers

  func createConfiguration(url: URL) -> GamingVideoUploaderConfiguration {
    GamingVideoUploaderConfiguration(videoURL: url, caption: "Cool Video")
  }
}
