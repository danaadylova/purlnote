import Flutter
import UIKit

#if canImport(FoundationModels)
import FoundationModels
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PurlnoteStepReader") {
      StepReader.register(with: registrar)
    }
  }
}

/// Turns a page of pattern text into steps with Apple's on-device model,
/// for the Steps view. Only the on-device model is used, never Apple's cloud,
/// so the pattern's text stays on the phone.
///
/// Dart side: lib/steps/step_builder.dart (OnDeviceModel), on the channel
/// "purlnote/steps":
///   isAvailable -> Bool
///   readPage(text, section?) -> [[section, label, side, text]]
final class StepReader {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "purlnote/steps", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        result(isAvailable())
      case "readPage":
        guard let arguments = call.arguments as? [String: Any], let text = arguments["text"] as? String else {
          result(FlutterError(code: "bad_arguments", message: "readPage needs text", details: nil))
          return
        }
        let section = arguments["section"] as? String
        Task {
          let reply: Any
          do {
            reply = try await readPage(text: text, section: section)
          } catch {
            reply = FlutterError(code: "model_failed", message: error.localizedDescription, details: nil)
          }
          // Flutter expects replies on the main thread.
          DispatchQueue.main.async { result(reply) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func isAvailable() -> Bool {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      if case .available = SystemLanguageModel.default.availability {
        return true
      }
    }
    #endif
    return false
  }

  static func readPage(text: String, section: String?) async throws -> [[String: String]] {
    #if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      let session = LanguageModelSession(instructions: instructions)
      let prompt = """
        The pattern so far was in this section: \(section ?? "none").

        Pattern text:
        \(text)
        """
      let response = try await session.respond(to: prompt, generating: PageSteps.self)
      return response.content.steps.map { step in
        ["section": step.section, "label": step.label, "side": step.side, "text": step.text]
      }
    }
    #endif
    throw StepReaderError.unavailable
  }

  static let instructions = """
    You split knitting and crochet pattern text into steps a knitter follows one at a time.
    Each row or round is its own step. Each separate written instruction is its own step.
    Copy the pattern's words and numbers exactly. Never change, add up or leave out a number.
    Keep every size number exactly as written, with all its brackets, for example "88 (96, 104) [112, 120]". Never shorten a size list.
    Keep "repeat" instructions as their own step, worded as in the pattern.
    Leave out page headers, footers, copyright lines, abbreviation lists and photo captions.
    """
}

enum StepReaderError: Error {
  case unavailable
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct PageSteps {
  @Guide(description: "Every instruction on the page, in order: one per row, round or separate instruction.")
  var steps: [ModelStep]
}

@available(iOS 26.0, *)
@Generable
struct ModelStep {
  @Guide(description: "The section heading this step belongs to, such as Body or Sleeves. Empty if none.")
  var section: String

  @Guide(description: "The row or round label as written, such as Row 14, Rnd 3 or Rows 3-4. Empty if not a row.")
  var label: String

  @Guide(description: "RS or WS if the pattern says which side. Otherwise empty.")
  var side: String

  @Guide(description: "The instruction itself, copied exactly, without the row label.")
  var text: String
}
#endif
