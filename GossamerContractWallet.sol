pragma solidity ^0.5.11;
import { CErc20, CToken, ReentrancyGuard } from "./CERC20.sol";
import { ERC20Interface } from "./ERC20.sol";
import "./SafeMath.sol";

/// @title Gossamer Contract Wallet
/// @author Tarik Bellamine & Kevin Kim
/// @notice The contract is intended to be used as a user contract wallet that will allow users to easily interact with Compound's money
/// market contracts through the Gossamer UI

contract GossamerContractWallet is ReentrancyGuard {
  using SafeMath for uint256;
  address public userAddress;
  mapping(address => bool) public adminAddresses;

  /// @notice Logged when a contract is created
  /// @param userAddress The wallet address of the user
  /// @param userIdentifier1 Offchain user identifier
  /// @param userIdentifier2 Offchain user identifier
  /// @param userIdentifier3 Offchain user identifier
  /// @param contractVersion The wallet address of the user
  event GossamerContractCreation(address indexed userAddress, string indexed userIdentifier1, string userIdentifier2, string userIdentifier3, string contractVersion);

  /// @notice Logged when a token is approved
  /// @param userAddress The wallet address of the user
  /// @param tokenAddress The address of the token to approve for transfers
  event GossamerApproval(address indexed userAddress, address indexed tokenAddress);

  /// @notice Logged when a user deposits to this contract wallet and their deposit is supplied to Compound's money market
  /// @param userAddress The wallet address of the user
  /// @param amountSuppliedToken The amount of tokens deposited to the contract wallet
  /// @param amountSuppliedCToken The amount of cTokens returned to the contract wallet from the money market
  /// @param tokenAddress The address of the token deposited
  event GossamerDeposit(address indexed userAddress, uint256 amountSuppliedToken, uint256 amountSuppliedCToken, address indexed tokenAddress);

  /// @notice Logged when there is a Compound error associated with supplying cTokens
  /// @param userAddress The wallet address of the user
  /// @param tokenAddress The address of the token deposited
  /// @param compoundErrorCode The Compound error code that maps to an error message on their developer docs
  event GossamerDepositError(address indexed userAddress, address indexed tokenAddress, uint256 indexed compoundErrorCode);

  /// @notice Logged when a user withdraws from Compound's money market and has tokens sent back to their address
  /// @param userAddress The wallet address of the user
  /// @param amountWithdrawnCToken The amount of cTokens being sent to Compound's money market to be converted to tokens
  /// @param principalWithdrawn The proportion of the withdrawal amount that the user originally deposited as principal
  /// @param interestWithdrawn The amount of tokens the user has earned on the principal being withdrawn
  /// @param tokenAddress The address of the token withdrawn
  event GossamerWithdrawal(address indexed userAddress, uint256 amountWithdrawnCToken, uint256 principalWithdrawn, uint256 interestWithdrawn, address indexed tokenAddress);

  /// @notice Logged when there is a Compound error associated with redeeming cTokens
  /// @param userAddress The wallet address of the user
  /// @param tokenAddress The address of the token withdrawn
  /// @param compoundErrorCode The Compound error code that maps to an error message on their developer docs
  event GossamerWithdrawalError(address indexed userAddress, address indexed tokenAddress, uint256 indexed compoundErrorCode);

  /// @notice The constructor's purpose is to define the user address that will receive funds when the withdrawal function is called as
  /// well as specifying the admin accounts that have permission to call this contract's functions on the user's behalf
  /// @param _userAddress The user's wallet address
  /// @param _adminAddressesArr Array of Gossamer admin addresses that are able to call this contract's protected functions on behalf of the user
  /// @param _userIdentifier1 Offchain user identifier
  /// @param _userIdentifier2 Offchain user identifier
  /// @param _userIdentifier3 Offchain user identifier
  constructor(address _userAddress, address [] memory _adminAddressesArr, string memory _userIdentifier1, string memory _userIdentifier2, string memory _userIdentifier3, string memory _contractVersion) public {
    userAddress = _userAddress;
    for (uint i = 0; i < _adminAddressesArr.length; i += 1) {
      adminAddresses[_adminAddressesArr[i]] = true;
    }
    emit GossamerContractCreation(_userAddress, _userIdentifier1, _userIdentifier2, _userIdentifier3, _contractVersion);
  }

  /// @notice Modifier that restricts the ability to call functions to just the user and admin addresses
  modifier onlyUserAndAdmins() {
    require((adminAddresses[msg.sender] || userAddress == msg.sender), "Only admin or user can access this contract's functions.");
    _;
  }


  /// -------------- Helper Functions --------------- ///
  /// @notice Getter function for Dai address
  /// @return Dai token address
  function daiAddress() internal pure returns (address) {
    return 0x89d24A6b4CcB1B6fAA2625fE562bDD9a23260359;
  }

  /// @notice Getter function for USDC address
  /// @return USDC token address
  function usdcAddress() internal pure returns (address) {
    return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  }

  /// @notice Getter function for cDAI address
  /// @return cDAI token address
  function cDAIAddress() internal pure returns (address) {
    return 0xF5DCe57282A584D2746FaF1593d3121Fcac444dC;
  }

  /// @notice Getter function for cUSDC address
  /// @return cUSDC token address
  function cUSDCAddress() internal pure returns (address) {
    return 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
  }

  /// @notice Returns address for the cToken contract corresponding to provided token address (either Dai or USDC)
  /// @param _tokenAddress The token contract address which we want the corresponding cToken contract address for (either Dai or USDC)
  /// @return cDAI or cUSDC cToken address
  function getCTokenAddress(address _tokenAddress) private pure returns (address) {
    if (_tokenAddress == daiAddress()) {
      return cDAIAddress();
    } else if (_tokenAddress == usdcAddress()) {
      return cUSDCAddress();
    } else {
      revert('The token address provided is not supported by Gossamer at this time');
    }
  }


  /// -------------- Core Functions --------------- ///
  /// @notice Approves the cToken contract to transfer any amount of tokens from this contract
  /// @param _tokenAddress The token contract address that will initiate the transfer
  function approveCTokenContract(address _tokenAddress) external onlyUserAndAdmins {
    address _cTokenAddress = getCTokenAddress(_tokenAddress);
    ERC20Interface(_tokenAddress).approve(_cTokenAddress,  (2 ** 256) - 1);
    emit GossamerApproval(userAddress, _tokenAddress);
  }

  /// @notice Supplies the entirety of this contract's token balance to Compound's money market contracts and adds the amount supplied to the principalHolder in state
  /// @param _tokenAddress The contract address of the token the user is supplying
  function supplyToMoneyMarket(address _tokenAddress) external onlyUserAndAdmins nonReentrant returns (uint256) {
    address _cTokenAddress = getCTokenAddress(_tokenAddress);
    uint256 _tokenBalance = ERC20Interface(_tokenAddress).balanceOf(address(this));
    uint256 _initialCTokenBalance = CErc20(_cTokenAddress).balanceOf(address(this));
    uint256 _mintStatus = CErc20(_cTokenAddress).mint(_tokenBalance);
    if (_mintStatus == 0) {
      emit GossamerDeposit(userAddress, _tokenBalance, CErc20(_cTokenAddress).balanceOf(address(this)).sub(_initialCTokenBalance), _tokenAddress);
    } else {
      emit GossamerDepositError(userAddress, _tokenAddress, _mintStatus);
    }
    return _mintStatus;
  }

  /// @notice Withdraws from Compound's money market contracts to this contract, subtracts the amount of principal being withdrawn
  /// from the principal holder in state, transfers 9.5% of interest earned fee to the Gossamer admin wallet, then transfers the user the remaining contract balance
  /// @param _tokenAddress The address of the token the user is withdrawing (i.e., DAI or USDC)
  /// @param _cTokensRequested The amount the user is attempting to withdraw (denominated in cTokens)
  /// @param _principal The amount of tokens the user is withdrawing from their principal balance (event logging purposes only)
  /// @param _interest The amount of tokens the user is withdrawing from their interest balance (event logging purposes only)
  function withdrawFromMoneyMarket(address _tokenAddress, uint256 _cTokensRequested, uint256 _principal, uint256 _interest) public onlyUserAndAdmins nonReentrant returns (uint256) {
    address _cTokenAddress = getCTokenAddress(_tokenAddress);
    uint256 _initalTokenBalance = ERC20Interface(_tokenAddress).balanceOf(address(this));
    uint256 _initialCTokenBalance = CErc20(_cTokenAddress).balanceOf(address(this));
    if (_cTokensRequested > _initialCTokenBalance) {
      _cTokensRequested = _initialCTokenBalance;
    }

    uint256 _redeemStatus = CErc20(_cTokenAddress).redeem(_cTokensRequested);
    if (_redeemStatus == 0) {
      uint256 _redeemedTokenBalance = ERC20Interface(_tokenAddress).balanceOf(address(this)).sub(_initalTokenBalance);
      require(ERC20Interface(_tokenAddress).transfer(userAddress, _redeemedTokenBalance), "Error transfering withdrawn tokens to user address");
      emit GossamerWithdrawal(userAddress, _cTokensRequested, _principal, _interest, _tokenAddress);
    } else {
      emit GossamerWithdrawalError(userAddress, _tokenAddress, _redeemStatus);
    }
    return _redeemStatus;
  }

  /// @notice Allows users to transfer ERC20s sent to this contract on accident back to their wallet. Does not allow cTokens to be withdrawn this way
  /// @param _tokenAddress The address of the token the user is withdrawing
  function withdrawERC20 (address _tokenAddress) external onlyUserAndAdmins {
    address _cDAIAddress = getCTokenAddress(daiAddress());
    address _cUSDCAddress = getCTokenAddress(usdcAddress());
    require(_tokenAddress != _cDAIAddress && _tokenAddress != _cUSDCAddress, "Please use the withdrawFromMoneyMarket function to withdraw from money markets");
    require(ERC20Interface(_tokenAddress).transfer(userAddress, ERC20Interface(_tokenAddress).balanceOf(address(this))), "Error transfering tokens to user address");
  }
}
