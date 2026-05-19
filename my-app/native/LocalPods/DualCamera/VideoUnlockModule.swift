import Foundation
import React
import StoreKit

@objc(VideoUnlockModule)
final class VideoUnlockModule: NSObject {
  private let videoUnlockProductID = "com.zhengning.dualcamera.video_unlock"
  private var updatesTask: Task<Void, Never>?

  override init() {
    super.init()
    if #available(iOS 15.0, *) {
      updatesTask = observeTransactionUpdates()
    }
  }

  deinit {
    updatesTask?.cancel()
  }

  @objc
  static func requiresMainQueueSetup() -> Bool {
    false
  }

  @objc(getProduct:rejecter:)
  func getProduct(resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    guard #available(iOS 15.0, *) else {
      rejectUnsupportedOS(reject)
      return
    }

    Task {
      do {
        let product = try await loadVideoUnlockProduct()
        resolve([
          "id": product.id,
          "displayName": product.displayName,
          "description": product.description,
          "displayPrice": product.displayPrice
        ])
      } catch {
        reject("product_load_failed", error.localizedDescription, error)
      }
    }
  }

  @objc(isVideoUnlocked:rejecter:)
  func isVideoUnlocked(resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    guard #available(iOS 15.0, *) else {
      rejectUnsupportedOS(reject)
      return
    }

    Task {
      resolve(await hasVideoUnlockEntitlement())
    }
  }

  @objc(purchaseVideoUnlock:rejecter:)
  func purchaseVideoUnlock(resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    guard #available(iOS 15.0, *) else {
      rejectUnsupportedOS(reject)
      return
    }

    Task {
      do {
        let product = try await loadVideoUnlockProduct()
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
          let transaction = try verifiedTransaction(from: verification)
          guard transaction.productID == videoUnlockProductID else {
            reject("unexpected_product", "The completed transaction does not match the video unlock product.", nil)
            return
          }
          await transaction.finish()
          resolve([
            "unlocked": true,
            "transactionId": String(transaction.id)
          ])

        case .userCancelled:
          resolve([
            "unlocked": await hasVideoUnlockEntitlement(),
            "cancelled": true
          ])

        case .pending:
          resolve([
            "unlocked": await hasVideoUnlockEntitlement(),
            "pending": true
          ])

        @unknown default:
          resolve([
            "unlocked": await hasVideoUnlockEntitlement(),
            "unknown": true
          ])
        }
      } catch {
        reject("purchase_failed", error.localizedDescription, error)
      }
    }
  }

  @objc(restorePurchases:rejecter:)
  func restorePurchases(resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    guard #available(iOS 15.0, *) else {
      rejectUnsupportedOS(reject)
      return
    }

    Task {
      do {
        try await AppStore.sync()
        resolve(["unlocked": await hasVideoUnlockEntitlement()])
      } catch {
        reject("restore_failed", error.localizedDescription, error)
      }
    }
  }

  private func rejectUnsupportedOS(_ reject: RCTPromiseRejectBlock) {
    reject("storekit2_unavailable", "Video unlock purchases require iOS 15 or later.", nil)
  }

  @available(iOS 15.0, *)
  private func loadVideoUnlockProduct() async throws -> Product {
    let products = try await Product.products(for: [videoUnlockProductID])
    guard let product = products.first(where: { $0.id == videoUnlockProductID }) else {
      throw VideoUnlockError.productUnavailable
    }
    return product
  }

  @available(iOS 15.0, *)
  private func hasVideoUnlockEntitlement() async -> Bool {
    for await result in Transaction.currentEntitlements {
      guard case .verified(let transaction) = result else {
        continue
      }

      if transaction.productID == videoUnlockProductID &&
        transaction.revocationDate == nil &&
        transaction.productType == .nonConsumable {
        return true
      }
    }

    return false
  }

  @available(iOS 15.0, *)
  private func observeTransactionUpdates() -> Task<Void, Never> {
    Task.detached { [videoUnlockProductID] in
      for await result in Transaction.updates {
        guard case .verified(let transaction) = result else {
          continue
        }

        if transaction.productID == videoUnlockProductID {
          await transaction.finish()
        }
      }
    }
  }

  @available(iOS 15.0, *)
  private func verifiedTransaction(from result: VerificationResult<Transaction>) throws -> Transaction {
    switch result {
    case .verified(let transaction):
      return transaction
    case .unverified(_, let error):
      throw error
    }
  }
}

private enum VideoUnlockError: LocalizedError {
  case productUnavailable

  var errorDescription: String? {
    switch self {
    case .productUnavailable:
      return "Video unlock product is unavailable. Check the App Store Connect product ID."
    }
  }
}
