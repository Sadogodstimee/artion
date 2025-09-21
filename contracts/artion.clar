;; Enhanced Artion Tipping Contract with Security and Error Handling

;; Data structures
(define-map tips uint { tipper: principal, recipient: principal, amount: uint, unlock-height: uint, claimed: bool })
(define-data-var next-tip-id uint u1)

;; Constants
(define-constant EMERGENCY_TIMEOUT u144000) ;; ~100 days in blocks

;; Error codes with clear meanings
(define-constant ERR-INVALID-AMOUNT u100)
(define-constant ERR-INVALID-LOCK u101)
(define-constant ERR-SELF-TIP u102)
(define-constant ERR-TIP-NOT-FOUND u200)
(define-constant ERR-UNAUTHORIZED u201)
(define-constant ERR-ALREADY-CLAIMED u202)
(define-constant ERR-STILL-LOCKED u203)
(define-constant ERR-TRANSFER-FAILED u300)
(define-constant ERR-EMERGENCY-NOT-AVAILABLE u400)

;; Enhanced tip function with security and validation
(define-public (tip (recipient principal) (amount uint) (lock uint))
  (let ((tip-id (var-get next-tip-id)))
    (begin
      ;; Comprehensive input validation
      (asserts! (> amount u0) (err ERR-INVALID-AMOUNT))
      (asserts! (and (> lock u0) (< lock u1000000)) (err ERR-INVALID-LOCK))
      (asserts! (not (is-eq tx-sender recipient)) (err ERR-SELF-TIP))
      
      ;; Safe transfer with error handling
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      
      ;; Store tip data with auto-generated ID
      (map-set tips tip-id { 
        tipper: tx-sender, 
        recipient: recipient, 
        amount: amount, 
        unlock-height: (+ stacks-block-height lock), 
        claimed: false 
      })
      
      ;; Increment tip ID for next tip
      (var-set next-tip-id (+ tip-id u1))
      (ok tip-id))))

;; Enhanced claim function with proper authorization and error handling
(define-public (claim (id uint))
  (let ((tip-data (unwrap! (map-get? tips id) (err ERR-TIP-NOT-FOUND))))
    (begin
      ;; CRITICAL: Only recipient can claim
      (asserts! (is-eq tx-sender (get recipient tip-data)) (err ERR-UNAUTHORIZED))
      
      ;; Check if already claimed
      (asserts! (not (get claimed tip-data)) (err ERR-ALREADY-CLAIMED))
      
      ;; Check if unlock period has passed
      (asserts! (>= stacks-block-height (get unlock-height tip-data)) (err ERR-STILL-LOCKED))
      
      ;; Transfer funds to recipient with proper error handling
      (try! (as-contract (stx-transfer? (get amount tip-data) tx-sender (get recipient tip-data))))
      
      ;; Mark as claimed using proper merge syntax
      (map-set tips id (merge tip-data { claimed: true }))
      (ok true))))

;; Emergency withdrawal mechanism for tippers
(define-public (emergency-withdraw (id uint))
  (let ((tip-data (unwrap! (map-get? tips id) (err ERR-TIP-NOT-FOUND))))
    (begin
      ;; Only original tipper can emergency withdraw
      (asserts! (is-eq tx-sender (get tipper tip-data)) (err ERR-UNAUTHORIZED))
      (asserts! (not (get claimed tip-data)) (err ERR-ALREADY-CLAIMED))
      
      ;; Must wait for emergency timeout period after unlock
      (asserts! (>= stacks-block-height (+ (get unlock-height tip-data) EMERGENCY_TIMEOUT)) (err ERR-EMERGENCY-NOT-AVAILABLE))
      
      ;; Return funds to original tipper
      (try! (as-contract (stx-transfer? (get amount tip-data) tx-sender (get tipper tip-data))))
      
      ;; Mark as claimed
      (map-set tips id (merge tip-data { claimed: true }))
      (ok true))))

;; Read-only functions for transparency and better UX
(define-read-only (get-tip (id uint))
  (map-get? tips id))

(define-read-only (get-next-tip-id)
  (var-get next-tip-id))

(define-read-only (get-tip-status (id uint))
  (match (map-get? tips id)
    tip-data (ok {
      tip: tip-data,
      blocks-until-unlock: (if (>= stacks-block-height (get unlock-height tip-data)) 
                             u0 
                             (- (get unlock-height tip-data) stacks-block-height)),
      can-claim: (and 
                   (>= stacks-block-height (get unlock-height tip-data))
                   (not (get claimed tip-data))),
      emergency-available: (and
                            (not (get claimed tip-data))
                            (>= stacks-block-height (+ (get unlock-height tip-data) EMERGENCY_TIMEOUT)))
    })
    (err ERR-TIP-NOT-FOUND)))

;; Check if a user can claim a specific tip
(define-read-only (can-claim-tip (id uint) (user principal))
  (match (map-get? tips id)
    tip-data (ok (and 
                   (is-eq user (get recipient tip-data))
                   (>= stacks-block-height (get unlock-height tip-data))
                   (not (get claimed tip-data))))
    (err ERR-TIP-NOT-FOUND)))

;; Get contract balance for transparency
(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender)))