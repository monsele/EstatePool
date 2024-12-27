// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract EstatePool is ERC1155, ERC1155Holder {
    //////////////////
    /////ERRORS/////
    error EstatePool__TransactionFailed();
    error EstatePool__CurrencyNotFound(string message);
    ///////////////////
    // State Variables
    ///////////////////

    TokenData[] private ListedTokens;
    AuctionData[] private auctions;
    Currency[] private CurrencyList;
    uint256 private tokenCounter;
    uint256 private auctionCounter;
    /// @dev mapping of tokenId to amount sold
    mapping(uint256 => uint256) private availableTokenAmount;
    ///@dev Mapping for tokenId -> tokendata
    mapping(uint256 => TokenData) private tokenMapping;
    /// @dev This refers to the user's total value bought
    mapping(address => uint256) private userTvl;
    /// @dev This is the user's total yields gained
    mapping(address => uint256) private totalYields;
    /// @dev This ties all the users to their respective tokens
    mapping(address => TokenData[]) private userTokens;
    /// @dev This mapping is for tracking Auctions
    mapping(uint256 => AuctionData) private auction;
    /// @dev this is a mapping of the byte representation of the currency code
    /// to the currency struct
    mapping(bytes32 => Currency) NameToFiat;

    ///////////////////
    // Events
    ///////////////////
    event TokenListed(address indexed owner, string indexed name, uint256 indexed id);
    event TokenBought(address indexed from, address indexed to, uint256 indexed tokenid);
    event AuctionCreated(uint256 indexed auctionId, address indexed creator, uint256 indexed tokenId, uint256 amount);
    event TokenDelisted(uint256 indexed tokenId);

    event AuctionPaid(address indexed payer, address indexed owner, uint256 indexed auctionId, uint256 amount);

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, ERC1155Holder)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    constructor(string memory _uri) ERC1155(_uri) {
        //https://myapp.com/{tokenId}
        _setURI(_uri);
        tokenCounter = 0;
        auctionCounter = 0;
    }

    // [Rest of your contract code remains the same...]

    struct TokenData {
        string Name;
        uint256 Id;
        address Owner;
        uint256 TotalPlots;
        uint256 AmountToBeSold;
        EstateType Type;
        bool Active;
    }

    struct UserTokenData {
        // TokenData tokenData;
        uint256 tokenId;
        string Name;
        string Description;
        uint256 amountOwned;
    }

    struct AuctionData {
        uint256 TokenId;
        uint256 AmountToSell;
        address Owner;
        uint256 auctionId;
        bool completed;
    }

    struct Currency {
        uint256 Id;
        string Name;
        string ShortForm;
        string ImageUri;
    }

    enum EstateType {
        Land,
        Houses,
        Commercial,
        ApartMent
    }

    /// function to list and provide tokens of an asset
    /// @param name The name of asset
    /// @param totalPlots Total available plots
    /// @param amtToSell Amount willing to see to investors
    /// @param estateType Estate Type enum
    /// @param userAddress Estate Type enum
    function CreateAsset(
        string memory name,
        uint256 totalPlots,
        uint256 amtToSell,
        EstateType estateType,
        address userAddress
    ) external returns (TokenData memory) {
        tokenCounter = getTokenCounter() + 1;
        TokenData memory tokenData =
            TokenData(name, tokenCounter, userAddress, totalPlots, amtToSell, estateType, false);
        _mint(userAddress, tokenCounter, totalPlots, "");
        ListedTokens.push(tokenData);
        availableTokenAmount[tokenCounter] = amtToSell;
        tokenMapping[tokenCounter] = tokenData;
        _setApprovalForAll(userAddress, address(this), true);
        emit TokenListed(tokenData.Owner, tokenData.Name, tokenData.Id);
        return tokenData;
    }

    function create(string memory name, string memory shortForm, string memory imageUri) external {
        bytes32 key = keccak256(abi.encodePacked(shortForm));
        require(NameToFiat[key].Id == 0, "Short form already exist");
        tokenCounter = getTokenCounter() + 1;
        Currency memory currency = Currency(tokenCounter, name, shortForm, imageUri);
        CurrencyList.push(currency);

        NameToFiat[key] = currency;
    }

    function mintCurrency(string memory shortForm, uint256 amount, address user) external {
        bytes32 key = keccak256(abi.encodePacked(shortForm));
        Currency memory currency = NameToFiat[key];

        _mint(user, currency.Id, amount, "");
        _setApprovalForAll(user, address(this), true);
    }

    function burnCurrency(string memory shortForm, uint256 amount, address user) external {
        bytes32 key = keccak256(abi.encodePacked(shortForm));
        Currency memory currency = NameToFiat[key];
        _burn(user, currency.Id, amount);
    }

    /// @param tokenId  this is the Id of the token on the ListedToken array
    /// @param purchaseAmt this is the amount of units that the user wants to purchase
    /// @param payAmount This is the expected amount the user should send to the smart contract
    /// @param userAddress This is the address the paymaster is sponsoring and represent the user that made the call
    /// @param currencyCode This is for the currency code of the payment token
    function BuyPlot(
        uint256 tokenId,
        uint256 purchaseAmt,
        uint256 payAmount,
        address userAddress,
        string memory currencyCode
    ) external {
        // 1. CHECKS
        TokenData memory data = tokenMapping[tokenId];
        address recipient = data.Owner; // Added back the recipient address
        require(userAddress != data.Owner, "Owner Cannot buy listed property");
        uint256 availableAmt = availableTokenAmount[tokenId];
        require(purchaseAmt <= availableAmt, "Purchase amount exceeds the available amount");

        bytes32 key = keccak256(abi.encodePacked(currencyCode));
        Currency memory currency = NameToFiat[key];
        if (currency.Id == 0) {
            revert EstatePool__CurrencyNotFound("Currency cannot be found");
        }

        // 2. EFFECTS
        availableTokenAmount[tokenId] = availableTokenAmount[tokenId] - purchaseAmt;
        userTvl[userAddress] = userTvl[userAddress] + payAmount;
        addTokenToUser(userAddress, tokenId);

        // 3. INTERACTIONS
        _safeTransferFrom(userAddress, recipient, currency.Id, payAmount, "0x");
        _safeTransferFrom(recipient, userAddress, tokenId, purchaseAmt, "0x");

        emit TokenBought(recipient, userAddress, tokenId);
    }

    function AuctionAsset(uint256 tokenId, uint256 amount, address userAddress) external {
        auctionCounter = getAuctionCounter() + 1;
        _safeTransferFrom(userAddress, address(this), tokenId, amount, "0x");

        auction[auctionCounter] = AuctionData(tokenId, amount, userAddress, auctionCounter, false);
        auctions.push(AuctionData(tokenId, amount, userAddress, auctionCounter, false));
        emit AuctionCreated(auctionCounter, userAddress, tokenId, amount);
        //return (true, auctionCounter);
    }

    /// @param auctionId  this is the Id of the auction
    /// @param amount This is the amount that you are paying in currency
    /// @param userAddress This is the address the paymaster is sponsoring and represent the user that made the call
    /// @param currencyCode This is for the currency code of the payment token
    function PayBid(uint256 auctionId, uint256 amount, string memory currencyCode, address userAddress) external {
        AuctionData storage auctionData = auction[auctionId];
        require(!auctionData.completed, "Auction is already completed");
        address owner = auctionData.Owner;
        uint256 amountToSell = auctionData.AmountToSell;
        uint256 tokenId = auctionData.TokenId;
        bytes32 key = keccak256(abi.encodePacked(currencyCode));
        Currency memory currency = NameToFiat[key];
        if (currency.Id == 0) {
            revert EstatePool__CurrencyNotFound("Currency cannot be found");
        }
        //Transfer the currency
        _safeTransferFrom(userAddress, owner, currency.Id, amount, "0x");

        // Transfer tokens to the bidder
        _safeTransferFrom(address(this), userAddress, tokenId, amountToSell, "");

        // Mark the auction as completed
        auctionData.completed = true;

        // Add token to user (make sure this function exists and works as expected)
        addTokenToUser(userAddress, tokenId);

        emit AuctionPaid(userAddress, owner, auctionId, amount);
    }

    function getListedTokens() external view returns (TokenData[] memory) {
        return ListedTokens;
    }
    /// @notice Get the available amount for a specific token
    /// @param tokenId The ID of the token to query
    /// @return Amount of tokens available

    function getAvailableTokenAmount(uint256 tokenId) external view returns (uint256) {
        return availableTokenAmount[tokenId];
    }

    /// @notice Get token data for a specific token ID
    /// @param tokenId The ID of the token to query
    /// @return TokenData struct containing token information
    function getTokenData(uint256 tokenId) external view returns (TokenData memory) {
        return tokenMapping[tokenId];
    }
    /// @notice Get total value locked for a specific user
    /// @param user Address of the user to query
    /// @return Total value locked for the user

    function getUserTvl(address user) external view returns (uint256) {
        return userTvl[user];
    }
    /// @notice Get total yields for a specific user
    /// @param user Address of the user to query
    /// @return Total yields for the user

    function getUserYields(address user) external view returns (uint256) {
        return totalYields[user];
    }
    /// @notice Get auction data for a specific token
    /// @param tokenId The ID of the token to query auction data for
    /// @return AuctionData struct containing auction information

    function getAuctionData(uint256 tokenId) external view returns (AuctionData memory) {
        return auction[tokenId];
    }

    function getUserTokensData(address user) external view returns (UserTokenData[] memory) {
        TokenData[] memory userTokenData = userTokens[user];
        //TokenData[] memory userTokenData2 = userTokensss[user];
        UserTokenData[] memory userTokenInfo = new UserTokenData[](userTokenData.length);
        uint256 tokenBalance = 0;
        for (uint256 i = 0; i < userTokenData.length; i++) {
            TokenData memory data = userTokenData[i];
            tokenBalance = balanceOf(user, data.Id);
            userTokenInfo[i] = UserTokenData(data.Id, data.Name, data.Name, tokenBalance);
        }
        return userTokenInfo;
    }

    function getUserStats(address user) external view returns (
    uint256 tvl,
    uint256 yields,
    TokenData[] memory tokens
) {
    return (
        userTvl[user],
        totalYields[user],
        userTokens[user]
    );
}

    function addTokenToUser(address user, uint256 tokenId) public returns (bool) {
        TokenData[] memory tokens = userTokens[user];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].Id == tokenId) {
                return true;
            }
        }
        userTokens[user].push(tokenMapping[tokenId]);
        return true;
    }

    function getTokenCounter() public view returns (uint256) {
        return tokenCounter;
    }
    function getAuctionCounter() public view returns (uint256) {
        return auctionCounter;
    }

    function getAuctions() external view returns (AuctionData[] memory) {
        return auctions;
    }

    function getUserBalance(string memory shortForm, address user) external view returns (uint256) {
        bytes32 key = keccak256(abi.encodePacked(shortForm));
        Currency memory currency = NameToFiat[key];
        return balanceOf(user, currency.Id);
    }

    function getKey(string memory shortForm) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(shortForm));
    }

    receive() external payable {}
}
