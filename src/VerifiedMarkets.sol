// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

import "./interfaces/Bond.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/CometInterface.sol";
import "./interfaces/VerifiedMarketsInterface.sol";

/**
 * @title Verified Markets 
 * @notice A Compound III operator to enable staking of collateral for real world assets to Compound.
 * @author Kallol Borah
 */
contract VerifiedMarkets is RWA{

  /// @notice The Comet contract
  Comet public immutable comet;

  //mapping issuer to asset
  mapping(address => mapping(address => Asset)) private assets;

  //mapping issuer to collateral
  mapping(address => mapping(address => Collateral)) private guarantees;

  //events
  event NewRWA(address indexed issuer, address indexed asset, address bond, uint256 apy, string issuingDocs, uint256 faceValue);
  event PurchasedRWA(address indexed collateralProvider, address indexed asset, address bond, uint256 amount);
  event PostedCollateral(address indexed issuer, address indexed asset, address collateral, uint256 amount);
  event Borrowed(address indexed borrower, address indexed base, uint256 amount);
  event Repaid(address indexed borrower, address indexed base, uint256 amount);
  event BorrowerRedeemed(address indexed borrower, address bond, address asset, uint256 amount);
  event LenderRedeemed(address indexed lender, address bond, address asset, uint256 amount);

  /**
   * @notice Construct a new operator.
   * @param comet_ The Comet contract.
   **/
  constructor(Comet comet_) payable {
    comet = comet_;
  }

  //RWA issuer submits asset details and bond issued that can be purchased to provide collateral to the RWA issuer for it to post to Compound
  function submitNewRWA(address asset, address bond, uint256 apy, string memory issuingDocs, uint256 faceValue) override external {
    require(asset!=address(0x0) && bond!=address(0x0) && apy>0 && faceValue>0, "RWA submission : Invalid request");
    RWA.Asset memory rwa = RWA.Asset({
      bond: bond,
      apy: apy,
      issuingDocs: issuingDocs,
      faceValue: faceValue
    });
    assets[msg.sender][asset] = rwa; 
    emit NewRWA(msg.sender, asset, bond, apy, issuingDocs, faceValue);
  }

  function voteOnRWA(address asset, bool ballot) override external {
    //to decide whether to implement or not
  }

  //comet user acts as credit enhancer and buys bond to provide collateral to RWA issuer
  function buyRWA(address asset, address bond, uint256 amount) override external {
    require(asset!=address(0x0) && bond!=address(0x0) && amount>0, "RWA Collateral provisioning: Invalid");
    if(Bond(bond).requestPurchase(amount, msg.sender, bytes32(abi.encodePacked(IERC20(asset).name())), asset)){
      emit PurchasedRWA(msg.sender, asset, bond, amount);
    }
  }

  //posting collateral from RWA issuer to Compound
  function postCollateral(address asset, address collateral, uint256 amount) override external {
    require(asset!=address(0x0) && collateral!=address(0x0) && amount>0, "Comet Collateral provisioning: Invalid");
    IERC20(asset).approve(msg.sender, amount);
    comet.supplyFrom(msg.sender, asset, collateral, amount);
    RWA.Collateral memory guarantee = RWA.Collateral({
      collateral: collateral,
      collateralAmount: amount,
      borrowed: 0 
    });
    guarantees[msg.sender][asset] = guarantee; 
    emit PostedCollateral(msg.sender, asset, collateral, amount);
  }

  //borrows base asset from Compound supplied to borrower
  function borrowBase(address base, uint256 amount) override external {
    require(base!=address(0x0) && amount>comet.baseBorrowMin(), "Borrowing base : Invalid");
    comet.withdrawTo(msg.sender, base, amount);
    guarantees[msg.sender][base].borrowed = amount;
    emit Borrowed(msg.sender, base, amount);
  }

  //repays base asset to Compound from borrower who withdraws collateral posted earlier
  function repayBase(address base, uint256 amount) override external {
    require(base!=address(0x0) && amount>1, "Repaying base : Invalid");
    IERC20(base).approve(msg.sender, amount);
    comet.supplyFrom(msg.sender, base, base, amount);
    uint256 collateralToWithdraw = comet.getAssetInfoByAddress(base).borrowCollateralFactor * amount;
    comet.withdrawTo(msg.sender, guarantees[msg.sender][base].collateral, collateralToWithdraw);
    emit Repaid(msg.sender, base, amount);
  }

  //redemption of bond by RWA issuer to free up RWA tokens
  function redeeemRWA(address asset, address bond, uint256 amount) override external {
    require(asset!=address(0x0) && bond!=address(0x0) && amount>0, "RWA Redemption by Issuer: Invalid");
    Bond(bond).requestRedemption(amount, msg.sender, bytes32(abi.encodePacked(IERC20(asset).name())), asset);
    emit BorrowerRedeemed(msg.sender, bond, asset, amount);
  }

  //redemption of bond by collateral provider that purchased the bond issued by the RWA issuer
  function sellRWA(address asset, address bond, uint256 amount) override external {
    require(asset!=address(0x0) && bond!=address(0x0) && amount>0, "RWA Redemption by Collateral provider : Invalid");
    Bond(bond).requestRedemption(amount, msg.sender, bytes32(abi.encodePacked(IERC20(asset).name())), asset);
    emit LenderRedeemed(msg.sender, bond, asset, amount);
  }

}


