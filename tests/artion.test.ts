import { describe, expect, it } from "vitest";
import { Cl, ClarityType, SomeCV, TupleCV } from "@stacks/transactions";

const CONTRACT = "artion";
const ERR = {
  INVALID_AMOUNT: 100n,
  UNAUTHORIZED: 201n,
  ALREADY_CLAIMED: 202n,
  STILL_LOCKED: 203n,
  EMERGENCY_NOT_AVAILABLE: 400n,
  BATCH_PARTIAL_FAILURE: 502n,
  CANNOT_CANCEL: 501n,
};
const EMERGENCY_TIMEOUT = 144000n;

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

const makeTip = (sender: string, recipient: string, amount: bigint, lock: bigint) =>
  simnet.callPublicFn(
    CONTRACT,
    "tip",
    [Cl.standardPrincipal(recipient), Cl.uint(amount), Cl.uint(lock)],
    sender,
  );

const unwrapSomeTuple = (cv: unknown): TupleCV => {
  expect(cv).toHaveClarityType(ClarityType.OptionalSome);
  return (cv as SomeCV).value as TupleCV;
};

describe("artion tipping contract", () => {
  it("creates tips and tracks ids for tipper and recipient", () => {
    const amount = 1_000_000n;
    const lock = 2n;

const { result: tipResult } = makeTip(wallet1, wallet2, amount, lock);
expect(tipResult).toBeOk(Cl.uint(1));

const tipData = simnet.callReadOnlyFn(CONTRACT, "get-tip", [Cl.uint(1)], deployer).result;
const tipTuple = unwrapSomeTuple(tipData);
expect(tipTuple.value.tipper).toBePrincipal(wallet1);
expect(tipTuple.value.recipient).toBePrincipal(wallet2);
expect(tipTuple.value.amount).toBeUint(amount);
expect(tipTuple.value.claimed).toBeBool(false);

    const userTips = simnet
      .callReadOnlyFn(CONTRACT, "get-user-tips", [Cl.standardPrincipal(wallet1)], deployer)
      .result;
    expect(userTips).toBeList([Cl.uint(1)]);

    const recipientTips = simnet
      .callReadOnlyFn(CONTRACT, "get-recipient-tips", [Cl.standardPrincipal(wallet2)], deployer)
      .result;
    expect(recipientTips).toBeList([Cl.uint(1)]);

    const nextTipId = simnet.callReadOnlyFn(CONTRACT, "get-next-tip-id", [], deployer).result;
    expect(nextTipId).toBeUint(2);
  });

  it("allows recipients to claim after unlock and cleans active lists", () => {
    const amount = 5000n;
    const lock = 1n;
    const tipId = 1n;

    const { result: tipResult } = makeTip(wallet1, wallet2, amount, lock);
    expect(tipResult).toBeOk(Cl.uint(tipId));

    simnet.mineEmptyBlocks(Number(lock));

    const { result: claimResult } = simnet.callPublicFn(
      CONTRACT,
      "claim",
      [Cl.uint(tipId)],
      wallet2,
    );
    expect(claimResult).toBeOk(Cl.bool(true));

const tipData = simnet.callReadOnlyFn(CONTRACT, "get-tip", [Cl.uint(tipId)], deployer).result;
const tipTuple = unwrapSomeTuple(tipData);
expect(tipTuple.value.claimed).toBeBool(true);

    const claimable = simnet
      .callReadOnlyFn(CONTRACT, "get-claimable-tips", [Cl.standardPrincipal(wallet2)], wallet2)
      .result;
    expect(claimable).toBeList([]);

    const activeTippers = simnet
      .callReadOnlyFn(CONTRACT, "get-user-tips", [Cl.standardPrincipal(wallet1)], deployer)
      .result;
    expect(activeTippers).toBeList([]);

    const activeRecipients = simnet
      .callReadOnlyFn(CONTRACT, "get-recipient-tips", [Cl.standardPrincipal(wallet2)], deployer)
      .result;
    expect(activeRecipients).toBeList([]);
  });

  it("rejects claims from non-recipients or while still locked", () => {
    const lock = 5n;
    const tipId = 1n;

    const { result: tipResult } = makeTip(wallet1, wallet2, 250n, lock);
    expect(tipResult).toBeOk(Cl.uint(tipId));

    const { result: unauthorized } = simnet.callPublicFn(
      CONTRACT,
      "claim",
      [Cl.uint(tipId)],
      wallet1,
    );
    expect(unauthorized).toBeErr(Cl.uint(ERR.UNAUTHORIZED));

    const { result: locked } = simnet.callPublicFn(
      CONTRACT,
      "claim",
      [Cl.uint(tipId)],
      wallet2,
    );
    expect(locked).toBeErr(Cl.uint(ERR.STILL_LOCKED));

    simnet.mineEmptyBlocks(Number(lock));
    const { result: claimResult } = simnet.callPublicFn(
      CONTRACT,
      "claim",
      [Cl.uint(tipId)],
      wallet2,
    );
    expect(claimResult).toBeOk(Cl.bool(true));
  });

  it("supports cancelling before unlock and blocks invalid cancel attempts", () => {
    const firstTipId = 1n;
    const { result: openTip } = makeTip(wallet1, wallet2, 800n, 3n);
    expect(openTip).toBeOk(Cl.uint(firstTipId));

    const { result: cancelResult } = simnet.callPublicFn(
      CONTRACT,
      "cancel-tip",
      [Cl.uint(firstTipId)],
      wallet1,
    );
    expect(cancelResult).toBeOk(Cl.bool(true));

    const { result: cancelAgain } = simnet.callPublicFn(
      CONTRACT,
      "cancel-tip",
      [Cl.uint(firstTipId)],
      wallet1,
    );
    expect(cancelAgain).toBeErr(Cl.uint(ERR.ALREADY_CLAIMED));

    const secondTipId = 2n;
    const { result: lateTip } = makeTip(wallet1, wallet2, 900n, 1n);
    expect(lateTip).toBeOk(Cl.uint(secondTipId));
    simnet.mineEmptyBlocks(1);
    const { result: lateCancel } = simnet.callPublicFn(
      CONTRACT,
      "cancel-tip",
      [Cl.uint(secondTipId)],
      wallet1,
    );
    expect(lateCancel).toBeErr(Cl.uint(ERR.CANNOT_CANCEL));

    const thirdTipId = 3n;
    const { result: unauthorizedTip } = makeTip(wallet1, wallet2, 700n, 2n);
    expect(unauthorizedTip).toBeOk(Cl.uint(thirdTipId));
    const { result: unauthorizedCancel } = simnet.callPublicFn(
      CONTRACT,
      "cancel-tip",
      [Cl.uint(thirdTipId)],
      wallet2,
    );
    expect(unauthorizedCancel).toBeErr(Cl.uint(ERR.UNAUTHORIZED));
  });

  it("only allows emergency withdraw after the timeout for the original tipper", () => {
    const tipId = 1n;
    const lock = 1n;

    const { result: tipResult } = makeTip(wallet1, wallet2, 1000n, lock);
    expect(tipResult).toBeOk(Cl.uint(tipId));

    const { result: earlyWithdraw } = simnet.callPublicFn(
      CONTRACT,
      "emergency-withdraw",
      [Cl.uint(tipId)],
      wallet1,
    );
    expect(earlyWithdraw).toBeErr(Cl.uint(ERR.EMERGENCY_NOT_AVAILABLE));

    const blocksToMine = Number(EMERGENCY_TIMEOUT + lock + 1n);
    simnet.mineEmptyBlocks(blocksToMine);

    const { result: withdrawResult } = simnet.callPublicFn(
      CONTRACT,
      "emergency-withdraw",
      [Cl.uint(tipId)],
      wallet1,
    );
    expect(withdrawResult).toBeOk(Cl.bool(true));

    const tipData = simnet.callReadOnlyFn(CONTRACT, "get-tip", [Cl.uint(tipId)], deployer).result;
    const tipTuple = unwrapSomeTuple(tipData);
    expect(tipTuple.value.claimed).toBeBool(true);
  });

  it("handles batch tips and claims when data align", () => {
    const recipients = Cl.list([Cl.standardPrincipal(wallet2), Cl.standardPrincipal(wallet2)]);
    const amounts = Cl.list([Cl.uint(200n), Cl.uint(300n)]);
    const locks = Cl.list([Cl.uint(1n), Cl.uint(1n)]);

    const { result: batchTipResult } = simnet.callPublicFn(
      CONTRACT,
      "batch-tip",
      [recipients, amounts, locks],
      wallet1,
    );
    expect(batchTipResult).toBeOk(Cl.list([Cl.uint(1), Cl.uint(2)]));

    simnet.mineEmptyBlocks(1);
    const { result: batchClaimResult } = simnet.callPublicFn(
      CONTRACT,
      "batch-claim",
      [Cl.list([Cl.uint(1), Cl.uint(2)])],
      wallet2,
    );
    expect(batchClaimResult).toBeOk(Cl.uint(2));

    const remainingClaimable = simnet
      .callReadOnlyFn(CONTRACT, "get-claimable-tips", [Cl.standardPrincipal(wallet2)], wallet2)
      .result;
    expect(remainingClaimable).toBeList([]);
  });

  it("fails batch claim when any entry is not claimable", () => {
    const tipId = 1n;
    const { result: tipResult } = makeTip(wallet1, wallet2, 400n, 5n);
    expect(tipResult).toBeOk(Cl.uint(tipId));

    const { result: batchClaimResult } = simnet.callPublicFn(
      CONTRACT,
      "batch-claim",
      [Cl.list([Cl.uint(tipId)])],
      wallet2,
    );
    expect(batchClaimResult).toBeErr(Cl.uint(ERR.BATCH_PARTIAL_FAILURE));
  });
});
