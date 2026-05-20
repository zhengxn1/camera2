import Foundation
import React
import StoreKit

@objc(VideoUnlockModule)
final class VideoUnlockModule: NSObject {
  private let videoUnlockProductID = "com.zhengning.dualcamera.unlock"
  private var updatesTask: Task<Void, Never>?

  override init() {
    super.init()
    NSLog("[VideoUnlock] module init")
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
        NSLog("[VideoUnlock] getProduct start")
        let product = try await loadVideoUnlockProduct()
        NSLog("[VideoUnlock] getProduct success id=%@ price=%@", product.id, product.displayPrice)
        resolve([
          "id": product.id,
          "displayName": product.displayName,
          "description": product.description,
          "displayPrice": product.displayPrice
        ])
      } catch {
        NSLog("[VideoUnlock] getProduct failed: %@", error.localizedDescription)
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
      NSLog("[VideoUnlock] isVideoUnlocked start")
      let unlocked = await hasVideoUnlockEntitlement()
      NSLog("[VideoUnlock] isVideoUnlocked result=%d", unlocked)
      resolve(unlocked)
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
        NSLog("[VideoUnlock] purchase start")
        let product = try await loadVideoUnlockProduct()
        NSLog("[VideoUnlock] purchase product loaded id=%@ price=%@", product.id, product.displayPrice)
        NSLog("[VideoUnlock] product.purchase begin")
        let result = try await product.purchase()
        NSLog("[VideoUnlock] product.purchase returned")

        switch result {
        case .success(let verification):
          NSLog("[VideoUnlock] purchase success; verifying transaction")
          let transaction = try verifiedTransaction(from: verification)
          NSLog("[VideoUnlock] transaction verified id=%llu product=%@", transaction.id, transaction.productID)
          guard transaction.productID == videoUnlockProductID else {
            NSLog("[VideoUnlock] unexpected product id=%@", transaction.productID)
            reject("unexpected_product", "The completed transaction does not match the video unlock product.", nil)
            return
          }
          await transaction.finish()
          NSLog("[VideoUnlock] transaction finished id=%llu", transaction.id)
          resolve([
            "unlocked": true,
            "transactionId": String(transaction.id)
          ])

        case .userCancelled:
          NSLog("[VideoUnlock] purchase user cancelled")
          resolve([
            "unlocked": await hasVideoUnlockEntitlement(),
            "cancelled": true
          ])

        case .pending:
          NSLog("[VideoUnlock] purchase pending")
          resolve([
            "unlocked": await hasVideoUnlockEntitlement(),
            "pending": true
          ])

        @unknown default:
          NSLog("[VideoUnlock] purchase unknown result")
          resolve([
            "unlocked": await hasVideoUnlockEntitlement(),
            "unknown": true
          ])
        }
      } catch {
        NSLog("[VideoUnlock] purchase failed: %@", error.localizedDescription)
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
        NSLog("[VideoUnlock] restore start")
        try await AppStore.sync()
        let unlocked = await hasVideoUnlockEntitlement()
        NSLog("[VideoUnlock] restore result unlocked=%d", unlocked)
        resolve(["unlocked": unlocked])
      } catch {
        NSLog("[VideoUnlock] restore failed: %@", error.localizedDescription)
        reject("restore_failed", error.localizedDescription, error)
      }
    }
  }

  private func rejectUnsupportedOS(_ reject: RCTPromiseRejectBlock) {
    reject("storekit2_unavailable", "Video unlock purchases require iOS 15 or later.", nil)
  }

  @available(iOS 15.0, *)
  private func loadVideoUnlockProduct() async throws -> Product {
    NSLog("[VideoUnlock] load product ids=%@", videoUnlockProductID)
    let products = try await Product.products(for: [videoUnlockProductID])
    NSLog("[VideoUnlock] load product count=%ld", products.count)
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
          NSLog("[VideoUnlock] transaction update unverified")
          continue
        }

        if transaction.productID == videoUnlockProductID {
          NSLog("[VideoUnlock] transaction update finish id=%llu", transaction.id)
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
