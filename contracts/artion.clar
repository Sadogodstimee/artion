;; Enhanced Artion Tipping Contract with Security, Batch Operations, and Advanced Features

;; Data structures
(define-map tips uint { tipper: principal, recipient: principal, amount: uint, unlock-height: uint, claimed: bool })
(define-map user-tips principal (list 100 uint))
(define-map recipient-tips principal (list 100 uint))
(define-data-var next-tip-id uint u1)

;; Constants
(define-constant EMERGENCY_TIMEOUT u144000) ;; ~100 days in blocks
(define-constant MAX_BATCH_SIZE u10)

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
(define-constant ERR-BATCH-LIMIT-EXCEEDED u500)
(define-constant ERR-CANNOT-CANCEL u501)
(define-constant ERR-BATCH-PARTIAL-FAILURE u502)
(define-constant ERR-INVALID-BATCH-DATA u503)

;; Enhanced tip function with security, validation, and user tracking
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
      
      ;; Track tips for users (for batch operations and management)
      (map-set user-tips tx-sender 
        (unwrap-panic (as-max-len? 
          (append (default-to (list) (map-get? user-tips tx-sender)) tip-id) 
          u100)))
      
      (map-set recipient-tips recipient
        (unwrap-panic (as-max-len? 
          (append (default-to (list) (map-get? recipient-tips recipient)) tip-id) 
          u100)))
      
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

;; NEW: Batch claim function for recipients - Major efficiency improvement
(define-public (batch-claim (tip-ids (list 10 uint)))
  (let ((results (map claim-single tip-ids)))
    (begin
      (asserts! (<= (len tip-ids) MAX_BATCH_SIZE) (err ERR-BATCH-LIMIT-EXCEEDED))
      (if (is-some (index-of results (err u0)))
          (err ERR-BATCH-PARTIAL-FAILURE)
          (ok (len tip-ids))))))

;; Helper function for batch claiming
(define-private (claim-single (id uint))
  (match (map-get? tips id)
    tip-data (if (and 
                   (is-eq tx-sender (get recipient tip-data))
                   (not (get claimed tip-data))
                   (>= stacks-block-height (get unlock-height tip-data)))
                (begin
                  (unwrap-panic (as-contract (stx-transfer? (get amount tip-data) tx-sender (get recipient tip-data))))
                  (map-set tips id (merge tip-data { claimed: true }))
                  (ok true))
                (err u0))
    (err u0)))

;; NEW: Batch tip function for efficiency - Major functionality enhancement
(define-public (batch-tip (recipients (list 10 principal)) (amounts (list 10 uint)) (locks (list 10 uint)))
  (let ((recipient-count (len recipients))
        (amount-count (len amounts))
        (lock-count (len locks)))
    (begin
      ;; Ensure all lists have same length and within limits
      (asserts! (and (is-eq recipient-count amount-count) (is-eq amount-count lock-count)) (err ERR-INVALID-BATCH-DATA))
      (asserts! (<= recipient-count MAX_BATCH_SIZE) (err ERR-BATCH-LIMIT-EXCEEDED))
      (asserts! (> recipient-count u0) (err ERR-INVALID-BATCH-DATA))
      
      ;; Process batch tips
      (ok (fold process-batch-tip 
                (map create-tip-tuple recipients amounts locks)
                (list))))))

;; Helper function to create tip tuples for batch processing
(define-private (create-tip-tuple (recipient principal) (amount uint) (lock uint))
  { recipient: recipient, amount: amount, lock: lock })

;; Helper function for batch tipping
(define-private (process-batch-tip (tip-data { recipient: principal, amount: uint, lock: uint }) (acc (list 10 uint)))
  (match (tip (get recipient tip-data) (get amount tip-data) (get lock tip-data))
    tip-id (unwrap-panic (as-max-len? (append acc tip-id) u10))
    error-val acc))

;; NEW: Cancel tip function (before unlock period) - Enhanced user control
(define-public (cancel-tip (id uint))
  (let ((tip-data (unwrap! (map-get? tips id) (err ERR-TIP-NOT-FOUND))))
    (begin
      ;; Only tipper can cancel
      (asserts! (is-eq tx-sender (get tipper tip-data)) (err ERR-UNAUTHORIZED))
      (asserts! (not (get claimed tip-data)) (err ERR-ALREADY-CLAIMED))
      
      ;; Can only cancel before unlock period
      (asserts! (< stacks-block-height (get unlock-height tip-data)) (err ERR-CANNOT-CANCEL))
      
      ;; Return funds to tipper
      (try! (as-contract (stx-transfer? (get amount tip-data) tx-sender (get tipper tip-data))))
      
      ;; Mark as claimed (cancelled)
      (map-set tips id (merge tip-data { claimed: true }))
      (ok true))))

;; FIXED: Emergency withdrawal mechanism for tippers with proper transfer logic
(define-public (emergency-withdraw (id uint))
  (let ((tip-data (unwrap! (map-get? tips id) (err ERR-TIP-NOT-FOUND))))
    (begin
      ;; Only original tipper can emergency withdraw
      (asserts! (is-eq tx-sender (get tipper tip-data)) (err ERR-UNAUTHORIZED))
      (asserts! (not (get claimed tip-data)) (err ERR-ALREADY-CLAIMED))
      
      ;; Must wait for emergency timeout period after unlock
      (asserts! (>= stacks-block-height (+ (get unlock-height tip-data) EMERGENCY_TIMEOUT)) (err ERR-EMERGENCY-NOT-AVAILABLE))
      
      ;; FIXED: Correct transfer - from contract to tipper
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

;; NEW: Get all tips for a user (as tipper) - Enhanced user management
(define-read-only (get-user-tips (user principal))
  (default-to (list) (map-get? user-tips user)))

;; NEW: Get all tips for a recipient - Enhanced recipient management
(define-read-only (get-recipient-tips (recipient principal))
  (default-to (list) (map-get? recipient-tips recipient)))

;; NEW: Get claimable tips for a recipient - Improved UX
(define-read-only (get-claimable-tips (recipient principal))
  (filter is-claimable (get-recipient-tips recipient)))

;; Helper function to check if tip is claimable
(define-private (is-claimable (tip-id uint))
  (match (map-get? tips tip-id)
    tip-data (and 
               (>= stacks-block-height (get unlock-height tip-data))
               (not (get claimed tip-data)))
    false))

;; NEW: Get total claimable amount for a recipient - Financial overview
(define-read-only (get-total-claimable-amount (recipient principal))
  (fold sum-claimable-amounts (get-claimable-tips recipient) u0))

;; Helper function to sum claimable amounts
(define-private (sum-claimable-amounts (tip-id uint) (total uint))
  (match (map-get? tips tip-id)
    tip-data (+ total (get amount tip-data))
    total))

;; NEW: Get cancellable tips for a user - Enhanced tip management
(define-read-only (get-cancellable-tips (user principal))
  (filter is-cancellable (get-user-tips user)))

;; Helper function to check if tip is cancellable
(define-private (is-cancellable (tip-id uint))
  (match (map-get? tips tip-id)
    tip-data (and 
               (< stacks-block-height (get unlock-height tip-data))
               (not (get claimed tip-data)))
    false))

;; NEW: Get emergency withdrawable tips for a user
(define-read-only (get-emergency-withdrawable-tips (user principal))
  (filter is-emergency-withdrawable (get-user-tips user)))

;; Helper function to check if tip is emergency withdrawable
(define-private (is-emergency-withdrawable (tip-id uint))
  (match (map-get? tips tip-id)
    tip-data (and
               (not (get claimed tip-data))
               (>= stacks-block-height (+ (get unlock-height tip-data) EMERGENCY_TIMEOUT)))
    false))
